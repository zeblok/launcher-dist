# Zeblok Launcher — Easy Setup Guide

This guide shows you how to install the **Zeblok Launcher** on a Linux machine
(Ubuntu or Debian). You just copy a command, paste it into your terminal, and
press **Enter**. That's it.

You do **not** need a GitHub account, a password, or any key.

---

## What you need

- A computer or server running **Ubuntu or Debian** (64-bit).
- You can use `sudo` (admin rights) on it.
- An internet connection.

---

## 1. Install it

Copy these two lines, paste them into your terminal, and press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/zeblok/launcher-dist/main/setup-launcher.sh -o setup-launcher.sh
sudo bash setup-launcher.sh
```

That's the whole install. It automatically:

1. installs Docker (a tool the Launcher needs) if it isn't already there,
2. downloads the newest Launcher,
3. installs it and starts it.

Wait until it prints **"Launcher setup complete."** — you're done!

---

## 2. Open the Launcher

When the setup finishes, it shows the Launcher's web address — already filled in
with your server's own IP, like this:

```
http://203.0.113.10:5001
```

Just **copy that address and paste it into your web browser**. There's nothing to
change — the IP is already correct.

> Scrolled past it? Show the address again any time with:
> ```bash
> sudo grep '^APP_URL=' /opt/zbl-launcher/.env
> ```

> Make sure **port 5001** is open in your firewall / cloud security group, or the
> page won't open from another computer.

---

## 3. Check that it's running

```bash
zbl-launcher status
```

If it says the service is **active (running)**, everything is good.

---

## Update to the newest version (later)

Run these three lines any time to jump to the latest Launcher:

```bash
URL=$(curl -fsSL https://api.github.com/repos/zeblok/launcher-dist/releases/latest \
  | grep -o 'https://[^"]*_amd64\.deb' | head -1)
curl -fL -o /tmp/zbl-launcher.deb "$URL"
sudo dpkg -i /tmp/zbl-launcher.deb && rm -f /tmp/zbl-launcher.deb
```

Your settings are kept safe when you update.

---

## Handy commands

```bash
zbl-launcher status     # is it running?
zbl-launcher logs -f    # watch what it's doing (press Ctrl+C to stop)
zbl-launcher restart    # turn it off and on again
zbl-launcher version    # which version is installed
```

Want to change settings (like the port or passwords)?

```bash
zbl-launcher config     # opens the settings file, then restarts for you
```

---

## Having trouble?

- **`curl: command not found`** → install it first, then try again:
  ```bash
  sudo apt-get update && sudo apt-get install -y curl
  ```
- **The web page won't open** → wait about a minute (it takes a moment to
  start), run `zbl-launcher status`, and make sure port **5001** is open.
- **Still stuck?** → contact Zeblok support at zeblok@zeblok.com.
