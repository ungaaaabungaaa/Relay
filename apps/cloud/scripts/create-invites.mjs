const apiOrigin = process.env.RELAY_API_ORIGIN;
const adminCredential = process.env.RELAY_CLOUD_ADMIN_CREDENTIAL;
const rawEmails = process.env.RELAY_BETA_INVITE_EMAILS;

if (!apiOrigin || !adminCredential || !rawEmails) {
  throw new Error("Missing protected invite workflow configuration");
}

const origin = new URL(apiOrigin);
if (origin.protocol !== "https:") {
  throw new Error("Relay API origin must use HTTPS");
}

const emails = [
  ...new Set(
    rawEmails
      .split(/[\n,]/)
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean),
  ),
];
if (emails.length < 1 || emails.length > 25) {
  throw new Error("Protected beta list must contain between 1 and 25 emails");
}

for (const email of emails) {
  const response = await fetch(
    new URL("/cloud/v1/admin/invites", origin),
    {
      method: "POST",
      headers: {
        authorization: `Admin ${adminCredential}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ email }),
    },
  );
  if (!response.ok) {
    throw new Error(`Invite creation failed with status ${response.status}`);
  }
}

console.log(`Created ${emails.length} protected beta invite(s).`);
