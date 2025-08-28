Password on router: "password"

IDK MAN.. IDK... I GAVE UP ON THIS...

NOTE: Some commands might not work because PT is so ass

# Intercountry Network — Full Specification & Step‑by‑Step Runbook (Packet Tracer)

**Inside each country (same pattern):**  
- 1x Border Router (`X_Border`) connects to a **Core Switch** (`X_Core_SW`).  
- 3x Zone Routers (`X_Gov_R`, `X_Ent_R`, `X_Pub_R`) connect to `X_Core_SW`.  
- Each zone has its **own LAN /24**; each zone has 1x access switch and hosts.  
- **Enterprise Zone** has 3 servers: **DNS**, **DHCP**, **Web**, plus 1x PC.  
- **Kuronexus Public** is special: **VLAN 30/40/50** with **router‑on‑a‑stick** on `K_Pub_R`. VLAN 50 also has **Wi‑Fi** (WAP + smartphone + PC).

**Inter‑country WAN:**  
- A single **L2 2960 named `WAN_SW`** connects: `G_Border g0/0`, `R_Border g0/0`, `K_Border g0/0`.  
- `Y_Border` does **not** go to `WAN_SW`. Instead, **point‑to‑point**: `K_Border g0/1 <-> Y_Border g0/1` using /30.

**Models & names (keep consistent):**
- Routers: `G_Border(1941)`, `R_Border(1941)`, `K_Border(2911)`, `Y_Border(1941)`  
- Core switches: `G_Core_SW(2960)`, `R_Core_SW(2960)`, `K_Core_SW(2960)`, `Y_Core_SW(2960)`  
- Zone routers: `G_Gov_R/R_Ent_R/...` (all **1941**)  
- Zone switches: `G_Gov_SW`, `G_Ent_SW`, `G_Pub_SW`, ... (all **2960**)  
- Kuronexus Public WAP: `K_WAP` (**WAP‑PT**), phone `K_Phone`, laptop `K_WiPC`

**Cables (summary):**
- Router ↔ Switch: Copper Straight‑Through
- PC/Server ↔ Switch: Copper Straight‑Through
- WAP ↔ Switch: Copper Straight‑Through
- No serial links; all GigE

## 1) Addressing Plan (IPv4)

### 1.1 Core / Area 0 in each country (to Core Switch)
```
G Core: 10.10.0.0/24   G_Border=10.10.0.1,  G_Gov_R=10.10.0.2,  G_Ent_R=10.10.0.3,  G_Pub_R=10.10.0.4
R Core: 10.20.0.0/24   R_Border=10.20.0.1,  R_Gov_R=10.20.0.2,  R_Ent_R=10.20.0.3,  R_Pub_R=10.20.0.4
K Core: 10.30.0.0/24   K_Border=10.30.0.1,  K_Gov_R=10.30.0.2,  K_Ent_R=10.30.0.3,  K_Pub_R=10.30.0.4
Y Core: 10.40.0.0/24   Y_Border=10.40.0.1,  Y_Gov_R=10.40.0.2,  Y_Ent_R=10.40.0.3,  Y_Pub_R=10.40.0.4
```

### 1.2 Zone LANs (per country)
```
G: Gov 10.10.10.0/24 (GW=10.10.10.1),  Ent 10.10.20.0/24 (GW=10.10.20.1),  Pub 10.10.30.0/24 (GW=10.10.30.1)
R: Gov 10.20.10.0/24 (GW=10.20.10.1),  Ent 10.20.20.0/24 (GW=10.20.20.1),  Pub 10.20.30.0/24 (GW=10.20.30.1)
K: Gov 10.30.10.0/24 (GW=10.30.10.1),  Ent 10.30.20.0/24 (GW=10.30.20.1)
   Public VLANs on K_Pub_R g0/1 subinterfaces (router‑on‑a‑stick):
     VLAN 30 (Academy) 10.30.30.0/24 gateway 10.30.30.1
     VLAN 40 (Business) 10.30.40.0/24 gateway 10.30.40.1
     VLAN 50 (Communal) 10.30.50.0/24 gateway 10.30.50.1
Y: Gov 10.40.10.0/24 (GW=10.40.10.1),  Ent 10.40.20.0/24 (GW=10.40.20.1),  Pub 10.40.30.0/24 (GW=10.40.30.1)
```

### 1.3 Inter‑country WAN IPv4
```
WAN_SW (L2): connects G_Border g0/0, R_Border g0/0, K_Border g0/0
 G_Border g0/0 = 172.16.0.10/24
 R_Border g0/0 = 172.16.0.20/24
 K_Border g0/0 = 172.16.0.30/24

Point‑to‑Point K<->Y:
 K_Border g0/1 = 172.16.1.1/30
 Y_Border g0/1 = 172.16.1.2/30
```

---

## 2) Build & Wire (very literal)

For each country **X**:

1) Drag **X_Core_SW (2960)** + three **X_*_SW (2960)**.  
2) Drag routers: **X_Border (1941, except K=2911)** + **X_Gov_R**, **X_Ent_R**, **X_Pub_R** (1941).  
3) Wire:  
   - `X_Border g0/1` ↔ `X_Core_SW fa0/1`  
   - `X_Gov_R g0/0` ↔ `X_Core_SW fa0/2`  
   - `X_Ent_R g0/0` ↔ `X_Core_SW fa0/3`  
   - `X_Pub_R g0/0` ↔ `X_Core_SW fa0/4`  
   - `X_Gov_R g0/1` ↔ `X_Gov_SW fa0/1`  
   - `X_Ent_R g0/1` ↔ `X_Ent_SW fa0/1`  
   - `X_Pub_R g0/1` ↔ `X_Pub_SW fa0/1` (BUT in **K**, this is a **TRUNK** to carry VLAN 30/40/50)  
4) Add hosts: each zone gets 1x PC (except K Public has many), Enterprise gets **DNS, DHCP, Web servers**.  
5) Inter‑country:  
   - Place **WAN_SW (2960)**, connect it to `G_Border g0/0`, `R_Border g0/0`, `K_Border g0/0`.  
   - Connect `K_Border g0/1` ↔ `Y_Border g0/1` for the /30 link.

---

## 3) Base Router Config (hostnames & IPv4)

> The commands below are working packets we used; replace `X` with the country letter and IPs per the table.

### Example: **G_Gov_R (1941)**
```
enable
conf t
 hostname G_Gov_R
 interface g0/0
  ip address 10.10.0.2 255.255.255.0
  no shut
 interface g0/1
  ip address 10.10.10.1 255.255.255.0
  no shut
end
write
```

Repeat for **G_Ent_R (10.10.0.3 / 10.10.20.1)** and **G_Pub_R (10.10.0.4 / 10.10.30.1)**.  
Repeat same pattern for **R**, **K**, **Y** using their subnets.

### Border examples
```
G_Border (1941)
 g0/0 172.16.0.10/24 (WAN to WAN_SW)
 g0/1 10.10.0.1/24  (to G_Core_SW)

R_Border (1941)
 g0/0 172.16.0.20/24
 g0/1 10.20.0.1/24

K_Border (2911)
 g0/0 172.16.0.30/24 (to WAN_SW)
 g0/1 172.16.1.1/30  (to Y_Border)
 g0/2 10.30.0.1/24   (to K_Core_SW)

Y_Border (1941)
 g0/0 10.40.0.1/24   (to Y_Core_SW)
 g0/1 172.16.1.2/30  (to K_Border)
```

**Commands (sample: G_Border):**
```
enable
conf t
 hostname G_Border
 interface g0/0
  ip address 172.16.0.10 255.255.255.0
  no shut
 interface g0/1
  ip address 10.10.0.1 255.255.255.0
  no shut
end
write
```

---

## 4) OSPF (Internal Routing)

**Goal:** Multi‑Area per country. Area 0 on the core links (g0/0 to Core_SW). Each zone LAN is its own area (10/20/30).  
**Exception (K Public):** VLAN subifs must be in **Area 0** (PT quirk).

### Example: **G_Gov_R**
```
enable
conf t
 router ospf 1
  router-id 1.1.1.2
 network 10.10.0.0 0.0.0.255 area 0
 network 10.10.10.0 0.0.0.255 area 10
end
write
```

**G_Ent_R**
```
router ospf 1
 router-id 1.1.1.3
 network 10.10.0.0 0.0.0.255 area 0
 network 10.10.20.0 0.0.0.255 area 20
```

**G_Pub_R**
```
router ospf 1
 router-id 1.1.1.4
 network 10.10.0.0 0.0.0.255 area 0
 network 10.10.30.0 0.0.0.255 area 30
```

**G_Border**
```
router ospf 1
 router-id 1.1.1.1
 network 10.10.0.0 0.0.0.255 area 0
```

**R, K, Y** mirror the above pattern with their 10.20.*, 10.30.*, 10.40.* ranges.  
**K_Pub_R (router‑on‑a‑stick):**
```
interface g0/1
 no ip address
!
interface g0/1.30
 encapsulation dot1Q 30
 ip address 10.30.30.1 255.255.255.0
 ip helper-address 10.30.20.11
 ip ospf 1 area 0
!
interface g0/1.40
 encapsulation dot1Q 40
 ip address 10.30.40.1 255.255.255.0
 ip helper-address 10.30.20.11
 ip ospf 1 area 0
!
interface g0/1.50
 encapsulation dot1Q 50
 ip address 10.30.50.1 255.255.255.0
 ip helper-address 10.30.20.11
 ip ospf 1 area 0
!
router ospf 1
 router-id 3.3.3.4
 network 10.30.0.0 0.0.0.255 area 0
```

**Switch `K_Pub_SW` trunking:**
```
enable
conf t
 vlan 30,40,50
 interface fa0/1
  switchport mode trunk
  switchport trunk allowed vlan 30,40,50
 interface fa0/2
  switchport mode access
  switchport access vlan 30
 interface fa0/3
  switchport mode access
  switchport access vlan 40
 interface fa0/4
  switchport mode access
  switchport access vlan 50
end
write
```

**Verify OSPF:**
```
show ip ospf neighbor
show ip ospf interface brief
show ip route | begin Gateway
```

---

## 5) DHCP (Enterprise DHCP + Relay)

**Enterprise servers get STATIC IPv4:**  
`X_DNS_SRV = x.20.10`, `X_DHCP_SRV = x.20.11`, `X_Web_SRV = x.20.12` (mask /24, GW x.20.1).

**Server GUI in PT (Services > DHCP):**
- **ON**, add pools per **zone**:
  - `G_GOV`   GW 10.10.10.1, DNS 10.10.20.10, Start 10.10.10.100, Mask 255.255.255.0, Max 100
  - `G_ENT`   GW 10.10.20.1, DNS 10.10.20.10, Start 10.10.20.100, ...
  - `G_PUB`   GW 10.10.30.1, DNS 10.10.20.10, Start 10.10.30.100, ...
- **Kuronexus Public VLAN pools:**
  - `K_VLAN30` GW 10.30.30.1, DNS 10.30.20.10, Start 10.30.30.100
  - `K_VLAN40` GW 10.30.40.1, DNS 10.30.20.10, Start 10.30.40.100
  - `K_VLAN50` GW 10.30.50.1, DNS 10.30.20.10, Start 10.30.50.100

**DHCP Relay on zone routers (VERY IMPORTANT):** put **ip helper-address** towards the Enterprise DHCP server:
```
! Government example (G_Gov_R)
interface g0/1
 ip helper-address 10.10.20.11
! Public example (G_Pub_R)
interface g0/1
 ip helper-address 10.10.20.11

! K Public subinterfaces already have helper-address lines above
```

**Verify:** set PCs to DHCP, `ipconfig /renew` (PT PC > Desktop). If you ever see **default gateway 0.0.0.0**, your pool is missing the **Default Gateway** or the client didn’t renew.

---

## 6) VLAN 50 Wireless (Kuronexus)

- Put **K_WAP** on `K_Pub_SW fa0/4` (access VLAN 50).  
- On WAP GUI: set SSID `K-Communal`, security (open for simplicity), DHCP **off** on WAP.  
- Connect **K_Phone** and **K_WiPC** to SSID `K-Communal`.  
- Both should receive IPs in **10.30.50.0/24** from central DHCP (via helper on `K_Pub_R g0/1.50`).

---

## 7) BGP (External Routing) + Redistribution

**ASNs:** `G=65010`, `R=65020`, `K=65030`, `Y=65040`.

### G_Border
```
enable
conf t
 router bgp 65010
  neighbor 172.16.0.20 remote-as 65020
  neighbor 172.16.0.30 remote-as 65030
  redistribute ospf 1
!
router ospf 1
 redistribute bgp 65010 subnets
end
write

show ip bgp summary
```

### R_Border
```
router bgp 65020
 neighbor 172.16.0.10 remote-as 65010
 neighbor 172.16.0.30 remote-as 65030
 redistribute ospf 1
!
router ospf 1
 redistribute bgp 65020 subnets
```

### K_Border (AS 65030)
```
router bgp 65030
 neighbor 172.16.0.10 remote-as 65010
 neighbor 172.16.0.20 remote-as 65020
 neighbor 172.16.1.2  remote-as 65040
 redistribute ospf 1
!
router ospf 1
 redistribute bgp 65030 subnets
```

### Y_Border (AS 65040)
```
router bgp 65040
 neighbor 172.16.1.1 remote-as 65030
 redistribute ospf 1
!
router ospf 1
 redistribute bgp 65040 subnets
```

**Verify:** on borders: `show ip route` should show **B** routes to other countries; on internal routers, you’ll see **O E2** for external subnets (BGP→OSPF redistribution).

---

## 8) DNS (per country)

**Goal:** `web.gk`, `web.rr`, `web.kr`, `web.ym` resolve to **local web servers**.

### Minimal (works in all PT versions)
On **G_DNS_SRV** (Services > DNS):
- Turn **DNS = On**
- Add **A**: `web.gk -> 10.10.20.12`
- Add **A**: `border.gk -> 172.16.0.10`
  - `web.rr -> 10.20.20.12`, `web.kr -> 10.30.20.12`, `web.ym -> 10.40.20.12`
Repeat on **R_DNS_SRV / K_DNS_SRV / Y_DNS_SRV** with local web IPs and `border.zz` entries.

**Clients** get the correct DNS via **DHCP pool (DNS field)** automatically.

---

## 9) ACLs (Government & Enterprise)

### 9.1 Government — only foreign Gov can reach Gov LAN; allow DHCP replies; block all others (but allow Gov to go out)
Apply **OUTBOUND** on **Gov router g0/1** (towards the Gov LAN).

**G_Gov_R**
```
enable
conf t
 ip access-list extended GOV-OUT
  remark Allow foreign Gov subnets to G_Gov LAN
  permit ip 10.20.10.0 0.0.0.255 10.10.10.0 0.0.0.255
  permit ip 10.30.10.0 0.0.0.255 10.10.10.0 0.0.0.255
  permit ip 10.40.10.0 0.0.0.255 10.10.10.0 0.0.0.255
  remark DHCP replies from Enterprise DHCP to Gov clients
  permit udp host 10.10.20.11 10.10.10.0 0.0.0.255 eq 68
  remark Optional: allow returning traffic
  permit icmp any 10.10.10.0 0.0.0.255 echo-reply
  permit tcp any 10.10.10.0 0.0.0.255 established
  remark Deny others into Gov
  deny ip any 10.10.10.0 0.0.0.255
  permit ip any any
 interface g0/1
  ip access-group GOV-OUT out
end
write
```

**R_Gov_R / K_Gov_R / Y_Gov_R** — same template (swap subnets).

### 9.2 Enterprise — only HTTPS, DNS, DHCP allowed from everyone; same‑country Gov gets **full** access
Apply **OUTBOUND** on **Ent router g0/1** (towards Enterprise LAN).

**G_Ent_R**
```
enable
conf t
 ip access-list extended ENT-OUT
  remark Same-country Gov full access
  permit ip 10.10.10.0 0.0.0.255 10.10.20.0 0.0.0.255
  remark HTTPS to any Enterprise host
  permit tcp any 10.10.20.0 0.0.0.255 eq 443
  remark DNS to local DNS
  permit tcp any host 10.10.20.10 eq 53
  permit udp any host 10.10.20.10 eq 53
  remark DHCP traffic
  permit udp any any eq 67
  permit udp any any eq 68
  remark Optional return traffic helpers
  permit icmp any 10.10.20.0 0.0.0.255 echo-reply
  permit tcp any 10.10.20.0 0.0.0.255 established
  remark Block the rest to Enterprise
  deny ip any 10.10.20.0 0.0.0.255
  permit ip any any
 interface g0/1
  ip access-group ENT-OUT out
end
write
```
Repeat for **R/K/Y Ent** (change subnets & DNS IP).

**Verify ACLs:**
```
show access-lists
show run interface g0/1
```

---

## 10) SSH/Telnet on Borders

Some PT versions need slightly different RSA syntax. Use this **safe** sequence:

```
enable
conf t
 hostname G_Border
 ip domain-name border.lab
 username netadmin secret password
 enable secret password

 crypto key generate rsa modulus 1024
! or
 crypto key generate rsa general-keys modulus 1024

 ip ssh version 2
 line vty 0 4
  transport input ssh telnet
  login local
  exec-timeout 10 0
 end
write
```

**DNS A records (on each DNS server):**
```
border.gk -> 172.16.0.10
border.rr -> 172.16.0.20
border.kr -> 172.16.0.30
border.ym -> 172.16.1.2
```

**Test from any PC:**
```
telnet border.gk
ssh -l netadmin border.kr
```

If `default line vty` errors, that’s normal (not a valid command on PT images). Configure lines as shown.

---

## 11) NAT/PAT (Gokouloryn only, even host rule)

**Goal:** PAT all **even last-octet** internal IPv4 to G_Border’s WAN IP (172.16.0.10).  
We can do this with a wildcard that **checks only the least significant bit** of the host octet.

On **G_Border**:
```
enable
conf t
 interface g0/1
  ip nat inside
 interface g0/0
  ip nat outside

! ACL that matches any 10.10.X.X where last octet is EVEN (LSB=0)
! Using wildcard 0.0.255.254 -> only the very last bit of the last octet is checked (must be 0)
 access-list 100 permit ip 10.10.0.0 0.0.255.254 any

 ip nat inside source list 100 interface g0/0 overload
end
write
```

**Test:** Add two static PCs in **G_Public**: one `.101` (odd) and `.102` (even). The even one should reach outside (e.g., ping a foreign web/DNS); odd may fail by design.

Check:
```
show ip nat translations
```

---

## 12) IPv6 for Rurinthia & Yamindralia + Tunnel over IPv4

### 12.1 Turn on IPv6 routing (all R & Y routers)
```
conf t
 ipv6 unicast-routing
end
write
```

### 12.2 Addressing scheme (consistent & simple)

**Rurinthia (2001:db8:20::/48)**  
- Core (g0/0 on each R_*_R): `2001:db8:20::/64`  
  - R_Border g0/0 = `2001:db8:20::1/64`
  - R_Gov_R g0/0 = `2001:db8:20::2/64`
  - R_Ent_R g0/0 = `2001:db8:20::3/64`
  - R_Pub_R g0/0 = `2001:db8:20::4/64`
- LANs:
  - R_Gov_R g0/1 = `2001:db8:20:10::1/64`
  - R_Ent_R g0/1 = `2001:db8:20:20::1/64`
  - R_Pub_R g0/1 = `2001:db8:20:30::1/64`

**Yamindralia (2001:db8:40::/48)**  
- Core: `2001:db8:40::/64`
  - Y_Border g0/0 = `2001:db8:40::1/64`
  - Y_Gov_R g0/0 = `2001:db8:40::2/64`
  - Y_Ent_R g0/0 = `2001:db8:40::3/64`
  - Y_Pub_R g0/0 = `2001:db8:40::4/64`
- LANs:
  - Y_Gov_R g0/1 = `2001:db8:40:10::1/64`
  - Y_Ent_R g0/1 = `2001:db8:40:20::1/64`
  - Y_Pub_R g0/1 = `2001:db8:40:30::1/64`

### 12.3 OSPFv3 (OSPF for IPv6) inside R & Y

**R_Border (IPv6 OSPFv3 only on core g0/0):**
```
conf t
 ipv6 unicast-routing
 interface g0/0
  ipv6 address 2001:db8:20::1/64
  ipv6 ospf 10 area 0
!
ipv6 router ospf 10
 router-id 2.2.2.1
end
write
```

**R_Gov_R**
```
conf t
 interface g0/0
  ipv6 address 2001:db8:20::2/64
  ipv6 ospf 10 area 0
 interface g0/1
  ipv6 address 2001:db8:20:10::1/64
  ipv6 ospf 10 area 10
!
ipv6 router ospf 10
 router-id 2.2.2.2
end
write
```

**R_Ent_R (area 20)** and **R_Pub_R (area 30)** analogous (`router-id 2.2.2.3 / 2.2.2.4`).

**Y routers** mirror the same with `2001:db8:40::/64` and router-ids `4.4.4.x`.

**Verify:**
```
show ipv6 ospf neighbor
show ipv6 route
```

### 12.4 IPv6-in-IPv4 Tunnel (R_Border ↔ Y_Border)

> **Important PT quirk:** On some PT images, interface names cannot be used as tunnel source; use **IPv4 addresses**. Static IPv6 routes must point to the **remote tunnel IPv6** next-hop (not the interface name).

**R_Border**
```
conf t
 interface Tunnel10
  tunnel mode ipv6ip
  tunnel source 172.16.0.20
  tunnel destination 172.16.1.2
  ipv6 address 2001:db8:99::1/64
  no shut
end
write
```

**Y_Border**
```
conf t
 interface Tunnel10
  tunnel mode ipv6ip
  tunnel source 172.16.1.2
  tunnel destination 172.16.0.20
  ipv6 address 2001:db8:99::2/64
  no shut
end
write
```

**Static IPv6 routes via the tunnel (use next-hop IPv6):**
```
R_Border: ipv6 route 2001:db8:40::/48 2001:db8:99::2
Y_Border: ipv6 route 2001:db8:20::/48 2001:db8:99::1
```

**Ensure the tunnel endpoints are reachable in IPv4** (they are, thanks to L2 WAN + /30 link + BGP).

**Verify:**
```
show ipv6 interface brief
show ipv6 route
ping 2001:db8:99::2
ping 2001:db8:40:20::1
```

---

## 13) Website Content (quick check)

On each Web server (Services > HTTP > On): make an index with country name in header and distinct color (assignment requirement).

---

## 14) End‑to‑End Verification Checklist

Run these in sequence and capture screenshots if needed.

**Routers (each):**
```
show ip int brief
show ip route | begin Gateway
show ip ospf neighbor
show ip ospf interface brief
show ip protocols
show access-lists
```

**Borders:**
```
show ip bgp summary
show ip route
show run | i ^hostname|^interface|ip address|helper-address|access-group
```

**K_Pub_SW:**
```
show vlan brief
show interfaces trunk
```

**DHCP servers:** (Services > DHCP): pools **ON**, each pool has **Default Gateway** and **DNS** set.

**Hosts:** `ipconfig /all` → verify IP, mask, gateway, DNS. If GW shows 0.0.0.0, fix the pool and renew.

**NAT (G_Border):**
```
show ip nat translations
```

**SSH/Telnet:** from any PC
```
telnet border.gk
ssh -l netadmin border.kr
```

**IPv6 (R & Y):**
```
show ipv6 interface brief
show ipv6 route
ping 2001:db8:99::2   (from R_Border)
ping 2001:db8:20:10::1 (from Y side back to R Gov, etc.)
```

---

## 15) Common Pitfalls We Hit (and fixes)

- **Forgot ip helper-address** on zone routers → clients stuck on `169.254.*` or GW `0.0.0.0`. **Fix:** add helper to the Enterprise DHCP.  
- **K_Pub_SW trunk not set** → VLANs don’t work. **Fix:** set trunk on fa0/1 to K_Pub_R; access VLANs on edge ports.  
- **OSPF on K_Pub_R** not advertising subifs → add `ip ospf 1 area 0` under **each subinterface**.  
- **SSH key command syntax** differs → try both `crypto key generate rsa modulus 1024` and `crypto key generate rsa general-keys modulus 1024`.  
- **Tunnel static route refused** when referencing interface → **use next-hop IPv6** (`ipv6 route ... 2001:db8:99::2`) instead of `Tunnel10`.  
- **Cannot use interface as tunnel source in PT** → use the **IPv4 address** (`tunnel source 172.16.0.20`).  
- **NAT “even last octet”** puzzle → wildcard `0.0.255.254` on `10.10.0.0` works (locks LSB=0).  
- **ACL side-effects** blocking return traffic → add `icmp echo-reply` and `tcp established` permits as shown.  
- **Clients can’t ping border.gk** → ensure DNS A records for `border.zz` exist on **each** DNS or point clients to correct DNS via DHCP.  
- **Line vty “default”** is not a command in PT → configure `line vty` directly, as shown.

---

## 16) One‑Shot Device‑by‑Device Command Blocks (copy/paste)

### Gokouloryn
**G_Border**
```
enable
conf t
 hostname G_Border
 interface g0/0
  ip address 172.16.0.10 255.255.255.0
  no shut
 interface g0/1
  ip address 10.10.0.1 255.255.255.0
  no shut
 router ospf 1
  router-id 1.1.1.1
  network 10.10.0.0 0.0.0.255 area 0
 router bgp 65010
  neighbor 172.16.0.20 remote-as 65020
  neighbor 172.16.0.30 remote-as 65030
  redistribute ospf 1
 router ospf 1
  redistribute bgp 65010 subnets
 ! NAT even-last-octet
 interface g0/1
  ip nat inside
 interface g0/0
  ip nat outside
 access-list 100 permit ip 10.10.0.0 0.0.255.254 any
 ip nat inside source list 100 interface g0/0 overload
 ! SSH/Telnet
 ip domain-name border.lab
 username netadmin secret password
 enable secret password
 crypto key generate rsa modulus 1024
 ip ssh version 2
 line vty 0 4
  transport input ssh telnet
  login local
  exec-timeout 10 0
end
write
```

**G_Gov_R**
```
enable
conf t
 hostname G_Gov_R
 interface g0/0
  ip address 10.10.0.2 255.255.255.0
  no shut
 interface g0/1
  ip address 10.10.10.1 255.255.255.0
  ip helper-address 10.10.20.11
  no shut
 router ospf 1
  router-id 1.1.1.2
  network 10.10.0.0 0.0.0.255 area 0
  network 10.10.10.0 0.0.0.255 area 10
 ip access-list extended GOV-OUT
  permit ip 10.20.10.0 0.0.0.255 10.10.10.0 0.0.0.255
  permit ip 10.30.10.0 0.0.0.255 10.10.10.0 0.0.0.255
  permit ip 10.40.10.0 0.0.0.255 10.10.10.0 0.0.0.255
  permit udp host 10.10.20.11 10.10.10.0 0.0.0.255 eq 68
  permit icmp any 10.10.10.0 0.0.0.255 echo-reply
  permit tcp any 10.10.10.0 0.0.0.255 established
  deny ip any 10.10.10.0 0.0.0.255
  permit ip any any
 interface g0/1
  ip access-group GOV-OUT out
end
write
```

**G_Ent_R**
```
enable
conf t
 hostname G_Ent_R
 interface g0/0
  ip address 10.10.0.3 255.255.255.0
  no shut
 interface g0/1
  ip address 10.10.20.1 255.255.255.0
  no shut
 router ospf 1
  router-id 1.1.1.3
  network 10.10.0.0 0.0.0.255 area 0
  network 10.10.20.0 0.0.0.255 area 20
 ip access-list extended ENT-OUT
  permit ip 10.10.10.0 0.0.0.255 10.10.20.0 0.0.0.255
  permit tcp any 10.10.20.0 0.0.0.255 eq 443
  permit tcp any host 10.10.20.10 eq 53
  permit udp any host 10.10.20.10 eq 53
  permit udp any any eq 67
  permit udp any any eq 68
  permit icmp any 10.10.20.0 0.0.0.255 echo-reply
  permit tcp any 10.10.20.0 0.0.0.255 established
  deny ip any 10.10.20.0 0.0.0.255
  permit ip any any
 interface g0/1
  ip access-group ENT-OUT out
end
write
```

**G_Pub_R**
```
enable
conf t
 hostname G_Pub_R
 interface g0/0
  ip address 10.10.0.4 255.255.255.0
  no shut
 interface g0/1
  ip address 10.10.30.1 255.255.255.0
  ip helper-address 10.10.20.11
  no shut
 router ospf 1
  router-id 1.1.1.4
  network 10.10.0.0 0.0.0.255 area 0
  network 10.10.30.0 0.0.0.255 area 30
end
write
```

*(R, K, Y command blocks mirror the above with their subnets. K_Pub_R uses subinterfaces & OSPF area 0 as shown earlier.)*
