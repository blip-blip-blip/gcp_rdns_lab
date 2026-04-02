# GCP Reverse DNS Lab - Architecture in ASCII

This file contains high-quality ASCII art versions of the Mermaid diagrams found in the main `README.md`. These are designed for clear viewing directly in the terminal or any text editor.

---

## 1. Overall System Architecture

```text
    Captured Events
    (Compute Engine)
    +-----------------------+
    | instances.*           |
    | forwardingRules.*     |-----.
    | globalForwardingRules |     |
    +-----------------------+     |
                                  v
                    +-----------------------------+
                    |          ADC Folder         |
                    | (YOUR_ADC_FOLDER_ID)        |
                    | include_children = true     |
                    +--------------+--------------+
                                   |
                                   | aggregated log sink
                                   v
                    +-----------------------------+
                    |    Pub/Sub: rrdns-events    |
                    |        (host project)       |
                    +--------------+--------------+
                                   |
                                   | push subscription
                                   | (OIDC auth)
                                   v
                    +-----------------------------+
                    |   Cloud Run: rrdns-updater  |
                    |  (us-central1, internal)    |
                    +--------------+--------------+
                                   |
                                   | dns.admin
                                   v
                    +-----------------------------+
                    |  Cloud DNS: nonprod-ptr-zone|
                    |    (10.10.in-addr.arpa.)    |
                    +-----------------------------+
```

---

## 2. Custom Zone Flow (The Solution)

```text
   +------------+      +------------+      +------------+
   |     VM     |      |     LB     |      |  Workbench |
   |  (insert)  |      |  (insert)  |      |  (insert)  |
   +-----+------+      +-----+------+      +-----+------+
         |                   |                   |
         '---------+---------+-------------------'
                   |
                   v
    +---------------------------------+
    |        Folder Log Sinks         |
    |    (include_children=true)      |
    +----------------+----------------+
                     |
                     | aggregated audit logs
                     v
    +---------------------------------+
    |      Pub/Sub: rrdns-events      |
    +----------------+----------------+
                     |
                     | push + OIDC auth
                     v
    +---------------------------------+
    |     Cloud Run: rrdns-updater    |
    +----------------+----------------+
                     |
                     | create / delete PTR
                     v
    +---------------------------------+
    |  Cloud DNS: 10.10.in-addr.arpa. |
    |  (custom naming, full control)  |
    +---------------------------------+
```

---

## 3. Comparison: Eventarc vs. Folder Sinks

### Eventarc (Scaling Problem)

```text
   [ App Project 1 ] ----> [ Eventarc Trigger ] --.
                                                  |
   [ App Project 2 ] ----> [ Eventarc Trigger ] --+--> [ Cloud Run ]
                                                  |
   [ App Project N ] ----> [ Eventarc Trigger ] --'
                                                  |
   [ New Project   ] ----> [ MANUAL SETUP REQ! ] -'
```

### Folder Log Sinks (Scaling Solution)

```text
   +-------------------------------------------------------+
   | ADC Folder (include_children=true)                    |
   |                                                       |
   |  [ Project 1 ]  [ Project 2 ]  [ New Project! ]       |
   |       |               |               |               |
   |       '---------------+---------------'               |
   |                       |                               |
   |                       v                               |
   |             +-------------------+                     |
   |             |  Folder Log Sink  |                     |
   +-------------+---------+---------+---------------------+
                           |
                           v
                 +-------------------+
                 | Pub/Sub & Pipeline|
                 +-------------------+
```

---

## 4. The "Gap" in Managed Zones

```text
   [ VM Created ] --------> [ Metadata Server ] --------> [ Managed PTR ]
                                                             (Auto)

   [ LB Created ] --------> [      GAP       ] --------> [  NO RECORD  ]
                               (This Lab Fixes This!)
```

---

## 🎨 (The Fun Stuff)

### 1. The Mascot: The Reverse Robin
Because "RRDNS" sounds like "Robin", and it's "Reverse" DNS... get it?

```text
       / \__
      (    @\___
      /         O
     /   (_____/
    /_____/   U
      | |
      | |
      vvv   <-- (Wait, he's upside down!)

    Actually, let's try again:

       _ _
      ( v )  <-- Feet in the air
       ) (
      (   )
       \ /
        V    <-- Beak on the ground
```

### 2. The "Missing PTR" Ghost
What happens to Load Balancers before this lab is applied.

```text
     .---.
    /     \
   | (O) (O) |  <-- Spooky!
   |    V    |
   |  /---\  |
    \/     \/
  "Where is my
   PTR record???"
```

### 3. Success!
The feeling when `nslookup` actually works.

```text
      \O/
       |
      / \
   "IT WORKS!"
```
