## Services

- n8n
- searxng
- karakeep
- openwebui
- postgres
- redis
- caddy
- watchtower

## Goals

- A self-hosted n8n that runs on docker. 
- To be able to access all of the services from the internet. However, this doesn't allow anyone to access them. 
- n8n will be publicly accessible, but require authentication. This is achieved using Tailscale, which has a free plan that will do all we need.

## Hostinger

 I use Hostinger with the KVM2 plan for setting this up, using Docker install. Once it is setup, either use the Hostinger web terminal interface or ssh into the server using the root user. You should see a `ssh root@ipaddress` command. Copy that and run it on your local machine. Enter the password you specified when you created the account. 

Clone this repo. cd into the n8n-docker-setup directory and run `./prep.sh` to prepare the system. Optionally review prep.sh first to see what it does.

Prep.sh will ask for 3 things: 

1. A username you want to login as (as it's better not to use root by best practice)
2. The password for the user
3. The domain name you want to use (that you already own) that you want the n8n server to be reached on.

After running the script, you will need to log out. Before logging back in, you can edit your ssh config file to make it easier to connect. Think of the name you would like to use to connect, for example `n8n`. If you don't have a config file, create one at `~/.ssh/config`. You want at least this entry:

```
Host n8n
    HostName ipaddress
    User theusernameyoucreated
    IdentityFile ~/.ssh/thekeyyoucreatedintheinstall
```

Save that. Then you can run `ssh n8n` to connect to your server. 

### Hostinger Firewall

Now go to the [Hostinger HPanel](https://hpanel.hostinger.com). Click **Manage** next to the VPS you created.  Under the panel with the stats for your VPS, click **Firewall**. Click the add firewall button and give it a name. Click the 3 dots and choose Edit. You want a rule that drops everything, then add a rule to accept HTTPS, and another to accept SSH. Set the source for all of them to be Any. Then make sure that firewall is enabled. 

## Tailscale

Then you need to get a Tailscale account and add you home machine to your tailnet. Do this by downloading the Tailscale app from the [Tailscale website](https://tailscale.com/).

### Create TSAUTHKEY

After its installed, you need a key to add your docker containers to the tailnet. The easiest way to do it is to add the key to a docker secret.

1.  Create a folder called `~/.config` on the home directory for the user you are logged in as. 
2.  Create a file called `tsauthkey` in the `~/.config` folder.
3.  Go to the tailscale admin page, click on Settings. On the left go to Keys. Click the button `Generate auth key...`.
4.  Enable `Reusable`. Click `Generate key`.
5.  Add the key to the `tsauthkey` file.
6.  Make the file only readable by the user: `chmod 600 ~/.config/tsauthkey`

### Install Tailscale on server

1.  Go to Machines 
2.  Click Add Device and choose Linux Server.
3.  Click Generate Install Script.
4.  Copy the script and run on your VPS. 
5.  Run `sudo tailscale up`


## n8n

1. Navigate into the n8n directory: `cd n8n-docker-setup/n8n`
2. Review the .env file created by prep.sh

   a. `N8N_HOST` should be the hostname of your server.
   b. `WEBHOOK_URL` should be the URL of your server.
   c. `GENERIC_TIMEZONE` should be your timezone. You'll need to update this.

4.  Start the n8n container: `docker compose up -d`

## Caddy

1. Navigate to the caddy directory: `cd ~/n8n-docker-setup/caddy`
2. prep.sh copied Caddyfile.example to Caddyfile and updated all the hostnames using your domain.
3. Edit the .env file and add your Cloudflare API Token. If you are not using Cloudflare for your domain's DNS, you have some research to do.

To get the Cloudflare API token:

1. Login to the Cloudflare dashboard
2. In the left sidebar, click Manage Account.
3. Click Account API Tokens.
4. Create a new token.
    a. Permissions should be Zone, Zone, Edit, and Zone, DNS, Edit. 
    b. Update Zone Resources to point to the domain used in prep.sh
5. When it shows you the token, copy it and paste it into the .env file.

Finally run `docker compose up -d`. This takes a bit to run. It is building a new version of Caddy with support for Cloudflare.

## Watchtower

This will update all the containers to the latest version every day at 4am

1. Navigate into the watchtower directory: `cd ~/n8n-docker-setup/watchtower`
2. Edit the .env file and change the `TZ` to where ever you are. 
3. Start the watchtower container: `docker compose up -d`

## Karakeep

Hopefully you have added the Tailscale app to your local machine, or wherever you have Ollama installed. You will need to edit ~/n8n-docker-setup/karakeep/.env` and change OLLAMA_BASE_URL to that machine with port 11434. Then make sure you have gemma3:12b, llava, and embeddinggemma:latest models pulled. 

Then run `docker compose up -d`