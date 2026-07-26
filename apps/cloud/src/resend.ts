type ResendOptions = {
  apiKey: string;
  from: string;
  fetch?: typeof globalThis.fetch;
};

function escapeHTML(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

export function createResendMagicLinkSender(
  options: ResendOptions,
): (email: string, url: string) => Promise<void> {
  const fetcher = options.fetch ?? globalThis.fetch;
  return async (email: string, url: string) => {
    const response = await fetcher("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: `Bearer ${options.apiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        from: options.from,
        to: [email],
        subject: "Sign in to Relay",
        html:
          `<p>Use this single-use link to sign in to Relay:</p>` +
          `<p><a href="${escapeHTML(url)}">Sign in to Relay</a></p>` +
          `<p>This link expires in ten minutes. If you did not request it, ignore this email.</p>`,
        text:
          `Sign in to Relay: ${url}\n\n` +
          "This single-use link expires in ten minutes. If you did not request it, ignore this email.",
      }),
    });
    if (!response.ok) throw new Error("Email delivery failed");
  };
}
