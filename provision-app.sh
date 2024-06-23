#!/bin/bash
set -euxo pipefail

# install dependencies.
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    jq \
    postgresql-client

# configure the postgresql clients to trust the Amazon RDS certificates.
install -o root -g root -m 700 -d ~/.postgresql
install -o root -g root -m 644 /dev/null ~/.postgresql/root.crt
wget -q \
    -O ~/.postgresql/root.crt \
    https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
install -o ubuntu -g ubuntu -m 700 -d /home/ubuntu/.postgresql
install -o ubuntu -g ubuntu -m 644 ~/.postgresql/root.crt /home/ubuntu/.postgresql/root.crt

# install node LTS.
# see https://github.com/nodesource/distributions#debinstall
NODE_MAJOR_VERSION=20
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR_VERSION.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
apt-get update
apt-get install -y nodejs
node --version
npm --version

# add the app user.
groupadd --system app
adduser \
    --system \
    --disabled-login \
    --no-create-home \
    --gecos '' \
    --ingroup app \
    --home /opt/app \
    app
install -d -o root -g app -m 750 /opt/app

# add the app user to the imds group to allow it to access the imds ip address.
usermod --append --groups imds app

# configure the postgresql clients to trust the Amazon RDS certificates.
install -o app -g app -m 700 -d /opt/app/.postgresql
install -o app -g app -m 644 ~/.postgresql/root.crt /opt/app/.postgresql/root.crt

# create an example http server and run it as a systemd service.
pushd /opt/app
cat >main.js <<EOF
import * as fs from "fs/promises";
import * as path from "path";
import http from "http";
import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";
import postgres from "postgres";

function createRequestListener(instanceIdentity, postgresClient) {
    return async (request, response) => {
        const instanceCredentials = await getInstanceCredentials();
        const postgresData = await getPostgresData(postgresClient);
        const serverAddress = \`\${request.socket.localAddress}:\${request.socket.localPort}\`;
        const clientAddress = \`\${request.socket.remoteAddress}:\${request.socket.remotePort}\`;
        const html = \`<!DOCTYPE html>
<html>
<head>
<style>
body {
    font-family: monospace;
    white-space: pre-wrap;
}
</style>
</head>
<body>
Instance ID: \${instanceIdentity.instanceId}
Instance Image ID: \${instanceIdentity.imageId}
Instance Region: \${instanceIdentity.region}
Instance Role: \${instanceCredentials.role}
Instance Credentials Expire At: \${instanceCredentials.credentials.Expiration}
Node.js Version: \${process.versions.node}
Server Address: \${serverAddress}
Client Address: \${clientAddress}
Request URL: \${request.url}
PostgreSQL Version: \${postgresData.version}
PostgreSQL User: \${postgresData.user}
PostgreSQL Random Quote: \${postgresData.quote}
</body>
</html>
\`;
        response.writeHead(200, {"Content-Type": "text/html"});
        response.write(html);
        response.end();
    };
}

async function getPostgresData(sql) {
    const infoResults = await sql\`
        select version() as version, current_user as user
    \`;
    const quoteResults = await sql\`
        select text || ' -- ' || author as quote
        from quote
        order by random()
        limit 1
    \`;
    const version = infoResults[0].version;
    const user = infoResults[0].user;
    const quote = quoteResults[0].quote;
    return {
        version: version,
        user: user,
        quote: quote,
    };
}

// see https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/client/ssm/command/GetParameterCommand/
async function getInstanceRoleParameter(region, instanceRole, parameterName) {
    const client = new SSMClient({
        region: region,
    });
    const response = await client.send(new GetParameterCommand({
        Name: \`/\${instanceRole}/\${parameterName}\`,
        WithDecryption: true,
    }));
    return response.Parameter.Value;
}

// see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html#instance-metadata-security-credentials
async function getInstanceCredentials() {
    const tokenResponse = await fetch("http://169.254.169.254/latest/api/token", {
        method: "PUT",
        headers: {
            "X-aws-ec2-metadata-token-ttl-seconds": 30,
        }
    });
    if (!tokenResponse.ok) {
        throw new Error(\`Failed to fetch instance token: \${tokenResponse.status} \${tokenResponse.statusText}\`);
    }
    const token = await tokenResponse.text();
    const instanceRoleResponse = await fetch(\`http://169.254.169.254/latest/meta-data/iam/security-credentials\`, {
        headers: {
            "X-aws-ec2-metadata-token": token,
        }
    });
    if (!instanceRoleResponse.ok) {
        throw new Error(\`Failed to fetch instance role: \${instanceRoleResponse.status} \${instanceRoleResponse.statusText}\`);
    }
    const instanceRole = (await instanceRoleResponse.text()).trim();
    const instanceCredentialsResponse = await fetch(\`http://169.254.169.254/latest/meta-data/iam/security-credentials/\${instanceRole}\`, {
        headers: {
            "X-aws-ec2-metadata-token": token,
        }
    });
    if (!instanceCredentialsResponse.ok) {
        throw new Error(\`Failed to fetch \${instanceRole} instance role credentials: \${instanceCredentialsResponse.status} \${instanceCredentialsResponse.statusText}\`);
    }
    const instanceCredentials = await instanceCredentialsResponse.json();
    return {
        role: instanceRole,
        credentials: instanceCredentials,
    };
}

// see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-identity-documents.html
// see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html
// see https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-metadata-v2-how-it-works.html
async function getInstanceIdentity() {
    const tokenResponse = await fetch("http://169.254.169.254/latest/api/token", {
        method: "PUT",
        headers: {
            "X-aws-ec2-metadata-token-ttl-seconds": 30,
        }
    });
    if (!tokenResponse.ok) {
        throw new Error(\`Failed to fetch instance token: \${tokenResponse.status} \${tokenResponse.statusText}\`);
    }
    const token = await tokenResponse.text();
    const instanceIdentityResponse = await fetch("http://169.254.169.254/latest/dynamic/instance-identity/document", {
        headers: {
            "X-aws-ec2-metadata-token": token,
        }
    });
    if (!instanceIdentityResponse.ok) {
        throw new Error(\`Failed to fetch instance metadata: \${instanceIdentityResponse.status} \${instanceIdentityResponse.statusText}\`);
    }
    const instanceIdentity = await instanceIdentityResponse.json();
    return instanceIdentity;
}

async function getPostgresConnectionString(region, role) {
    return await getInstanceRoleParameter(region, role, "secret/postgres");
}

async function getPostgresClient(connectionString) {
    // see https://github.com/porsager/postgres/blob/v3.4.4/src/index.js#L49-L50
    // see https://github.com/porsager/postgres/blob/v3.4.4/src/index.js#L535-L557
    return await postgres(connectionString, {
        database: "quotes",
        ssl: {
            ca: await fs.readFile(path.join(process.env.HOME, ".postgresql", "root.crt")),
        },
    });
}

async function main() {
    const command = process.argv[2];
    const instanceIdentity = await getInstanceIdentity();
    const instanceCredentials = await getInstanceCredentials();
    const postgresConnectionString = await getPostgresConnectionString(instanceIdentity.region, instanceCredentials.role);
    if (command == "get-postges-connection-string") {
        console.log(postgresConnectionString);
        return 0;
    }
    const postgresClient = await getPostgresClient(postgresConnectionString);
    const port = process.argv[2];
    const server = http.createServer(createRequestListener(instanceIdentity, postgresClient));
    server.listen(port);
}

await main();
EOF
# see https://www.npmjs.com/package/@aws-sdk/client-ssm
# renovate: datasource=npm depName=@aws-sdk/client-ssm
npm_aws_sdk_client_ssm_version='3.600.0'
# see https://www.npmjs.com/package/postgres
# renovate: datasource=npm depName=postgres
npm_postgres_version='3.4.4'
cat >package.json <<EOF
{
    "name": "app",
    "description": "example application",
    "version": "1.0.0",
    "license": "MIT",
    "type": "module",
    "main": "main.js",
    "dependencies": {
        "@aws-sdk/client-ssm": "$npm_aws_sdk_client_ssm_version",
        "postgres": "$npm_postgres_version"
    }
}
EOF
npm install
popd

# launch the app.
cat >/etc/systemd/system/app.service <<EOF
[Unit]
Description=Example Web Application
After=network.target

[Service]
Type=simple
User=app
Group=app
AmbientCapabilities=CAP_NET_BIND_SERVICE
Environment=NODE_ENV=production
ExecStart=/usr/bin/node main.js 80
WorkingDirectory=/opt/app
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF

# initialize the quotes database.
# NB in a real application, you should manage the database using something
#    like https://github.com/xataio/pgroll.
while true; do
    postgres_connection_string="$(node /opt/app/main.js get-postges-connection-string || true)"
    if [ -n "$postgres_connection_string" ]; then
        postgres_result="$(psql \
            --no-password \
            --tuples-only \
            --csv \
            --variable ON_ERROR_STOP=1 \
            --command "select 'ready'" \
            "$postgres_connection_string" \
            || true)"
        if [ "$postgres_result" = "ready" ]; then
            break
        fi
    fi
    sleep 15
done
psql \
    --no-password \
    --echo-all \
    --variable ON_ERROR_STOP=1 \
    "$postgres_connection_string" \
    <<'EOF'
\c postgres
select 'create database quotes' where not exists (select from pg_database where datname = 'quotes')\gexec
EOF
psql \
    --no-password \
    --echo-all \
    --variable ON_ERROR_STOP=1 \
    "$postgres_connection_string" \
    <<'EOF'
\c quotes
create table if not exists quote(id serial primary key, author varchar(80) not null, text varchar(255) not null, url varchar(255) null);
insert into quote(id, author, text, url) values(1, 'Homer Simpson', 'To alcohol! The cause of... and solution to... all of life''s problems.', 'https://en.wikipedia.org/wiki/Homer_vs._the_Eighteenth_Amendment') on conflict do nothing;
insert into quote(id, author, text, url) values(2, 'President Skroob, Spaceballs', 'You got to help me. I don''t know what to do. I can''t make decisions. I''m a president!', 'https://en.wikipedia.org/wiki/Spaceballs') on conflict do nothing;
insert into quote(id, author, text, url) values(3, 'Pravin Lal', 'Beware of he who would deny you access to information, for in his heart he dreams himself your master.', 'https://alphacentauri.gamepedia.com/Peacekeeping_Forces') on conflict do nothing;
insert into quote(id, author, text, url) values(4, 'Edsger W. Dijkstra', 'About the use of language: it is impossible to sharpen a pencil with a blunt axe. It is equally vain to try to do it with ten blunt axes instead.', 'https://www.cs.utexas.edu/users/EWD/transcriptions/EWD04xx/EWD498.html') on conflict do nothing;
insert into quote(id, author, text, url) values(5, 'Gina Sipley', 'Those hours of practice, and failure, are a necessary part of the learning process.', null) on conflict do nothing;
insert into quote(id, author, text, url) values(6, 'Henry Petroski', 'Engineering is achieving function while avoiding failure.', null) on conflict do nothing;
insert into quote(id, author, text, url) values(7, 'Jen Heemstra', 'Leadership is defined by what you do, not what you''re called.', 'https://twitter.com/jenheemstra/status/1260186699021287424') on conflict do nothing;
insert into quote(id, author, text, url) values(8, 'Ludwig van Beethoven', 'Don''t only practice your art, but force your way into its secrets; art deserves that, for it and knowledge can raise man to the Divine.', null) on conflict do nothing;
EOF

# try accessing the database as the app user.
pushd /opt/app
sudo -u app psql \
    --no-password \
    --echo-all \
    --variable ON_ERROR_STOP=1 \
    "$postgres_connection_string" \
    <<'EOF'
\c quotes
select version();
select current_user;
select current_database();
EOF
popd

# start the application.
systemctl enable app
systemctl start app

# try the application.
while ! wget -qO- http://localhost/try; do sleep 3; done
