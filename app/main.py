import base64
import os
import json
import re
import time
import logging
from flask import Flask, request

import google.auth
from googleapiclient import discovery

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DNS_PROJECT  = os.environ["DNS_PROJECT"]
DNS_ZONE_NAME = os.environ["DNS_ZONE_NAME"]
ZONE_IP_PREFIX = os.environ.get("ZONE_IP_PREFIX", "10.10.")


def get_credentials():
    credentials, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    return credentials


def ip_to_ptr_name(ip: str) -> str:
    octets = ip.split(".")
    return f"{octets[3]}.{octets[2]}.{octets[1]}.{octets[0]}.in-addr.arpa."


def create_ptr_record(ip: str, fqdn: str):
    if not ip.startswith(ZONE_IP_PREFIX):
        logger.info(f"IP {ip} outside zone prefix {ZONE_IP_PREFIX}, skipping")
        return

    ptr_name = ip_to_ptr_name(ip)
    dns = discovery.build("dns", "v1", credentials=get_credentials())

    existing_record = None
    try:
        result = dns.resourceRecordSets().list(
            project=DNS_PROJECT, managedZone=DNS_ZONE_NAME,
            name=ptr_name, type="PTR"
        ).execute()
        existing_record = result.get("rrsets", [None])[0] if result.get("rrsets") else None
    except Exception as e:
        logger.warning(f"Could not check existing record: {e}")

    if existing_record:
        if fqdn in existing_record.get("rrdatas", []):
            logger.info(f"PTR {ptr_name} -> {fqdn} already exists, skipping")
            return
        # IP reuse: replace old record with new one
        dns.changes().create(
            project=DNS_PROJECT,
            managedZone=DNS_ZONE_NAME,
            body={
                "deletions": [existing_record],
                "additions": [{"name": ptr_name, "type": "PTR", "ttl": 300, "rrdatas": [fqdn]}],
            }
        ).execute()
        logger.info(f"Replaced PTR: {ptr_name} -> {existing_record['rrdatas']} with {fqdn}")
        return

    dns.changes().create(
        project=DNS_PROJECT,
        managedZone=DNS_ZONE_NAME,
        body={"additions": [{"name": ptr_name, "type": "PTR", "ttl": 300, "rrdatas": [fqdn]}]}
    ).execute()
    logger.info(f"Created PTR: {ptr_name} -> {fqdn}")


def delete_ptr_by_fqdn(fqdn: str):
    dns = discovery.build("dns", "v1", credentials=get_credentials())
    try:
        result = dns.resourceRecordSets().list(
            project=DNS_PROJECT, managedZone=DNS_ZONE_NAME
        ).execute()
        for record in result.get("rrsets", []):
            if fqdn in record.get("rrdatas", []):
                dns.changes().create(
                    project=DNS_PROJECT,
                    managedZone=DNS_ZONE_NAME,
                    body={"deletions": [record]}
                ).execute()
                logger.info(f"Deleted PTR: {record['name']} -> {fqdn}")
                return
    except Exception as e:
        logger.error(f"Error deleting PTR for {fqdn}: {e}")
    logger.warning(f"No PTR record found for {fqdn}")


def get_instance_ip(project: str, zone: str, name: str, retries: int = 3):
    compute = discovery.build("compute", "v1", credentials=get_credentials())
    for attempt in range(retries):
        try:
            instance = compute.instances().get(
                project=project, zone=zone, instance=name
            ).execute()
            return instance.get("networkInterfaces", [{}])[0].get("networkIP")
        except Exception as e:
            logger.warning(f"Attempt {attempt + 1} to get instance IP failed: {e}")
            if attempt < retries - 1:
                time.sleep(2)
    return None


def get_forwarding_rule_ip(project: str, region: str, name: str, retries: int = 3):
    compute = discovery.build("compute", "v1", credentials=get_credentials())
    for attempt in range(retries):
        try:
            rule = compute.forwardingRules().get(
                project=project, region=region, forwardingRule=name
            ).execute()
            return rule.get("IPAddress")
        except Exception as e:
            logger.warning(f"Attempt {attempt + 1} to get forwarding rule IP failed: {e}")
            if attempt < retries - 1:
                time.sleep(2)
    return None


def get_global_forwarding_rule_ip(project: str, name: str, retries: int = 3):
    compute = discovery.build("compute", "v1", credentials=get_credentials())
    for attempt in range(retries):
        try:
            rule = compute.globalForwardingRules().get(
                project=project, forwardingRule=name
            ).execute()
            return rule.get("IPAddress")
        except Exception as e:
            logger.warning(f"Attempt {attempt + 1} to get global forwarding rule IP failed: {e}")
            if attempt < retries - 1:
                time.sleep(2)
    return None


def handle_instance_insert(proto_payload: dict):
    resource_name = proto_payload.get("resourceName", "")
    match = re.match(r"projects/([^/]+)/zones/([^/]+)/instances/([^/]+)", resource_name)
    if not match:
        return
    project, zone, name = match.groups()

    ip = get_instance_ip(project, zone, name)
    if not ip:
        logger.error(f"Could not get IP for instance {name} in {project}/{zone}")
        return

    fqdn = f"{name}.{zone}.c.{project}.internal."
    create_ptr_record(ip, fqdn)


def handle_instance_delete(proto_payload: dict):
    resource_name = proto_payload.get("resourceName", "")
    match = re.match(r"projects/([^/]+)/zones/([^/]+)/instances/([^/]+)", resource_name)
    if not match:
        return
    project, zone, name = match.groups()
    fqdn = f"{name}.{zone}.c.{project}.internal."
    delete_ptr_by_fqdn(fqdn)


def handle_forwarding_rule_insert(proto_payload: dict):
    resource_name = proto_payload.get("resourceName", "")
    match = re.match(r"projects/([^/]+)/regions/([^/]+)/forwardingRules/([^/]+)", resource_name)
    if not match:
        return
    project, region, name = match.groups()

    # Try audit log first, fall back to Compute API
    ip = (proto_payload.get("request", {}).get("IPAddress") or
          proto_payload.get("response", {}).get("IPAddress"))
    if ip and not re.match(r"^\d+\.\d+\.\d+\.\d+$", str(ip)):
        ip = None
    if not ip:
        ip = get_forwarding_rule_ip(project, region, name)

    if not ip:
        logger.error(f"Could not get IP for forwarding rule {name} in {project}/{region}")
        return

    fqdn = f"{name}.{region}.{project}.internal."
    create_ptr_record(ip, fqdn)


def handle_forwarding_rule_delete(proto_payload: dict):
    resource_name = proto_payload.get("resourceName", "")
    match = re.match(r"projects/([^/]+)/regions/([^/]+)/forwardingRules/([^/]+)", resource_name)
    if not match:
        return
    project, region, name = match.groups()
    fqdn = f"{name}.{region}.{project}.internal."
    delete_ptr_by_fqdn(fqdn)


def handle_global_forwarding_rule_insert(proto_payload: dict):
    resource_name = proto_payload.get("resourceName", "")
    match = re.match(r"projects/([^/]+)/global/forwardingRules/([^/]+)", resource_name)
    if not match:
        return
    project, name = match.groups()

    ip = (proto_payload.get("request", {}).get("IPAddress") or
          proto_payload.get("response", {}).get("IPAddress"))
    if ip and not re.match(r"^\d+\.\d+\.\d+\.\d+$", str(ip)):
        ip = None
    if not ip:
        ip = get_global_forwarding_rule_ip(project, name)

    if not ip:
        logger.error(f"Could not get IP for global forwarding rule {name} in {project}")
        return

    fqdn = f"{name}.global.{project}.internal."
    create_ptr_record(ip, fqdn)


def handle_global_forwarding_rule_delete(proto_payload: dict):
    resource_name = proto_payload.get("resourceName", "")
    match = re.match(r"projects/([^/]+)/global/forwardingRules/([^/]+)", resource_name)
    if not match:
        return
    project, name = match.groups()
    fqdn = f"{name}.global.{project}.internal."
    delete_ptr_by_fqdn(fqdn)


@app.route("/", methods=["POST"])
def handle_event():
    try:
        envelope = request.get_json(force=True)
        if not envelope:
            return "No data", 400

        # Unwrap Pub/Sub push envelope: {"message": {"data": "<base64>"}, ...}
        message = envelope.get("message", {})
        if not message:
            return "No message", 400
        body = json.loads(base64.b64decode(message["data"]).decode("utf-8"))

        proto_payload = body.get("protoPayload", {})
        method_name = proto_payload.get("methodName", "")

        if "instances.insert" in method_name:
            handle_instance_insert(proto_payload)
        elif "instances.delete" in method_name:
            handle_instance_delete(proto_payload)
        elif "globalForwardingRules.insert" in method_name:
            handle_global_forwarding_rule_insert(proto_payload)
        elif "globalForwardingRules.delete" in method_name:
            handle_global_forwarding_rule_delete(proto_payload)
        elif "forwardingRules.insert" in method_name:
            handle_forwarding_rule_insert(proto_payload)
        elif "forwardingRules.delete" in method_name:
            handle_forwarding_rule_delete(proto_payload)
        else:
            logger.info(f"Ignoring method: {method_name}")

        return "OK", 200

    except Exception as e:
        logger.exception(f"Unhandled error: {e}")
        return "Internal error", 500


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port)
