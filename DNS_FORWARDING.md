# DNS Forwarding & Caching on Android / Termux

This guide covers running local DNS forwarders, caching resolvers, and ad-blocking services (**AdGuard Home** and **dnsmasq**) on Android inside Termux, with detailed instructions for configuring both local on-device clients and network-wide LAN clients.

---

## 1. Android Networking Realities

### The Privileged Port Restriction (< 1024)
On Linux and Android, binding to ports below `1024` requires `CAP_NET_BIND_SERVICE` or root (`UID 0`).

- **Standard DNS Port:** UDP and TCP port `53`.
- **Unrooted Android:** Termux runs as an unprivileged application user (`u0_aXXX`). It **cannot** bind to port `53`. Any service started on port 53 will fail with `EACCES: Permission denied`.
- **Solution:** Configure your DNS service to listen on an unprivileged high port:
  - Standard unprivileged DNS ports: `5353`, `1053`, or `5354`.
  - Secure DNS ports: `8443` (DNS-over-HTTPS), `8530` (DNS-over-TLS).

### Rooted Android (`tsu` / Magisk / KernelSU / APatch)
If rooted, you can bind directly to port `53`. However:
- Android's internal `netd` daemon and Wi-Fi hotspot tethering may already occupy port `53` on `0.0.0.0` or `127.0.0.1`.
- If a port conflict occurs, bind the DNS server explicitly to your LAN Wi-Fi interface IP (e.g., `192.168.1.50:53`) rather than `0.0.0.0:53`.

---

## 2. Choosing a Solution: AdGuard Home vs. dnsmasq

| Feature | AdGuard Home | dnsmasq |
| :--- | :--- | :--- |
| **Architecture** | Single standalone Go binary | Ultra-lightweight C daemon |
| **Memory Footprint** | ~30 – 50 MB RAM | ~2 – 5 MB RAM |
| **User Interface** | Modern Web Dashboard (React embedded) | None (pure CLI / config file) |
| **DNS Caching** | In-memory, persistent, **optimistic caching** | In-memory TTL cache + negative caching |
| **Upstream Encryption** | Native DoH, DoT, DoQ, DNSCrypt | Plain unencrypted UDP/TCP DNS only |
| **Downstream Encryption** | Serves DoH/DoT/DoQ to clients directly | Plain DNS only |
| **Ad-Blocking Syntax** | Full ABP rules, wildcards, regex, exceptions | Plain hosts format (`0.0.0.0 domain.com`) |
| **Best For** | Full-featured ad-blocking & encrypted DNS | Invisible, low-memory local cache & forwarder |

---

## 3. AdGuard Home Configuration

### Overview
AdGuard Home bundles a high-performance DNS resolver, an embedded Web management interface, a rule-matching engine, and an automated blocklist updater into a single executable.

### Unrooted Termux Setup
Run AdGuard Home with custom configuration and work directories inside `$PREFIX`:

```bash
# Create directories
mkdir -p "$PREFIX/etc/adguardhome" "$PREFIX/var/lib/adguardhome"

# Run initial setup wizard on unprivileged ports
AdGuardHome \
  -c "$PREFIX/etc/adguardhome/AdGuardHome.yaml" \
  -w "$PREFIX/var/lib/adguardhome"
```

During the initial web wizard (access at `http://localhost:3000` or `http://<phone-ip>:3000`):
- **Web Interface Port:** Set to `3000` or `8080`.
- **DNS Server Port:** Set to `5353` (or `1053`).

### Recommended `AdGuardHome.yaml` Settings
```yaml
dns:
  bind_hosts:
    - 0.0.0.0
  port: 5353
  upstream_dns:
    - https://dns.quad9.net/dns-query
    - https://cloudflare-dns.com/dns-query
    - tls://dns.google
  cache_size: 10485760       # 10 MB in-memory cache
  cache_ttl_min: 300         # Cache entries for at least 5 minutes
  cache_ttl_max: 86400       # Max cache TTL: 24 hours
  cache_optimistic: true     # Serve stale cache immediately while refreshing in background
```

---

## 4. dnsmasq Configuration

### Overview
`dnsmasq` is a rock-solid, ultra-lightweight DNS forwarder and cache that consumes virtually zero system resources (< 5 MB RAM).

### Unrooted `dnsmasq.conf` Template
Place this configuration at `$PREFIX/etc/dnsmasq.conf`:

```conf
# Listen on unprivileged port 5353
port=5353

# Bind to all interfaces (or 127.0.0.1 for local device only)
listen-address=0.0.0.0
bind-interfaces

# Do not read /etc/resolv.conf
no-resolv

# Fast upstream DNS resolvers
server=1.1.1.1
server=8.8.8.8
server=9.9.9.9

# Query upstreams simultaneously and pick the fastest
all-servers

# DNS Cache settings
cache-size=5000
no-negcache                  # Set to false if you want to cache negative/NXDOMAIN responses
neg-ttl=300                  # Negative cache TTL in seconds

# Optional: Load adblock hosts file
# addn-hosts=/data/data/com.termux/files/usr/etc/adblock.hosts

# Local domain overrides (instant 0ms resolution)
address=/myserver.local/192.168.1.100
```

### Running dnsmasq
```bash
dnsmasq -C "$PREFIX/etc/dnsmasq.conf" -d
```

---

## 5. Client Configuration Guides

Assume the Android device running the DNS forwarder is at IP **`192.168.1.50`** and listening on port **`5353`** (or port **`8443`** for DoH).

---

### Scenario A: Configuring the Same Android Device (Local Device)

Because Android OS settings do not allow specifying custom DNS ports in standard Wi-Fi settings, use an unprivileged on-device loopback forwarder:

#### 1. Using RethinkDNS (Recommended — Open Source)
1. Install **RethinkDNS** from F-Droid or Google Play.
2. Open RethinkDNS $\to$ **DNS** $\to$ **Configure**.
3. Select **DNS-over-UDP/TCP** (Custom).
4. Enter:
   ```text
   127.0.0.1:5353
   ```
5. Toggle RethinkDNS **ON**.
   - RethinkDNS creates a local Android `VpnService` loopback (runs entirely on-device with zero external routing).
   - All app, browser, and background traffic on the phone is routed into your Termux DNS cache!

#### 2. Using PersonalDNSFilter
1. Install **personalDNSfilter** from F-Droid.
2. In **Advanced Settings** $\to$ **DNS Servers**, set:
   ```text
   127.0.0.1:5353
   ```
3. Enable the local VPN service.

#### 3. Command Line & Scripts Inside Termux
For CLI utilities, query the custom port directly:
```bash
# Using dig (from package dnsutils)
dig @127.0.0.1 -p 5353 example.com

# Using doggo
doggo @127.0.0.1:5353 example.com

# Using cURL with custom DNS resolver
curl --dns-servers 127.0.0.1:5353 https://example.com
```

---

### Scenario B: Configuring Other Devices on the Wi-Fi / LAN

Most client operating systems (Windows, macOS, iOS, Android Wi-Fi) expect DNS strictly on port 53. Here is how to route them to your unrooted phone:

#### Method 1: Modern Web Browsers via DNS-over-HTTPS (Easiest)
If running **AdGuard Home** with HTTPS enabled on port `8443`:

1. In **Chrome**, **Brave**, **Firefox**, or **Edge**:
   - Go to **Settings** $\to$ **Privacy and Security** $\to$ **Use Secure DNS**.
   - Choose **Custom Provider**.
   - Enter:
     ```text
     https://192.168.1.50:8443/dns-query
     ```
2. The browser encrypts and routes all DNS traffic directly to your phone, completely bypassing the port 53 limitation.

---

#### Method 2: Router Port Redirection (Network-Wide Coverage)
If your Wi-Fi router runs OpenWrt, DD-WRT, AsusWRT-Merlin, pfSense, or MikroTik:

1. In the router's **DHCP Server** settings, set the DNS server to your phone's IP (`192.168.1.50`).
2. Add a firewall NAT rule to redirect port 53 to port 5353:
   ```bash
   # OpenWrt / Linux iptables rule
   iptables -t nat -A PREROUTING -p udp -d 192.168.1.50 --dport 53 -j REDIRECT --to-ports 5353
   iptables -t nat -A PREROUTING -p tcp -d 192.168.1.50 --dport 53 -j REDIRECT --to-ports 5353
   ```
3. All devices on the home network query port 53 normally, and the router transparently handles port translation.

---

#### Method 3: Linux / Raspberry Pi Clients (`systemd-resolved`)
Edit `/etc/systemd/resolved.conf`:
```ini
[Resolve]
DNS=192.168.1.50:5353
FallbackDNS=1.1.1.1
Domains=~.
```
Restart `systemd-resolved`:
```bash
sudo systemctl restart systemd-resolved
```

---

#### Method 4: Windows Clients
Windows network GUI does not accept ports in IPv4 DNS settings. Use one of these solutions:

1. **YogaDNS (Recommended GUI tool):**
   - Download YogaDNS (free on Windows).
   - Under **DNS Servers**, add: `192.168.1.50` with port `5353` (protocol: Plain UDP or TCP).
   - Set rule: route all system queries through this server.

2. **Windows Built-in PortProxy (PowerShell as Admin):**
   Redirect local port 53 traffic to the phone's port 5353:
   ```powershell
   netsh interface portproxy add v4tov4 listenport=53 listenaddress=127.0.0.1 connectport=5353 connectaddress=192.168.1.50
   ```
   Then set your Windows IPv4 DNS server to `127.0.0.1`.

---

#### Method 5: Apple iOS & macOS Clients
1. Generate an Apple `.mobileconfig` DNS profile (using tools like *DNS Profile Creator* or AdGuard Home's built-in client configuration generator).
2. Point the DoH endpoint to:
   ```text
   https://192.168.1.50:8443/dns-query
   ```
3. Install the profile in iOS/macOS System Settings. All Apple system DNS traffic will route over HTTPS to your phone.
