/// <reference path="../types/nodemailer.d.ts" />

import nodemailer from "nodemailer";

export type AuthEmailPurpose = "email-verification" | "password-reset";

export type AuthEmailMessage = {
  purpose: AuthEmailPurpose;
  to: string;
  subject: string;
  text: string;
  html?: string;
  url: string;
  token: string;
};

export type AuthEmailSender = {
  send(message: AuthEmailMessage): Promise<void>;
};

export type EmailDeliveryResolution = {
  sender: AuthEmailSender | null;
  reason: string;
};

type EnvSource = Record<string, string | undefined>;

type FetchLike = (
  input: string | URL | Request,
  init?: RequestInit
) => Promise<Response>;

type SmtpTransport = {
  sendMail(message: {
    from: string;
    to: string;
    subject: string;
    text: string;
    html?: string;
  }): Promise<unknown>;
};

type SmtpTransportFactory = (options: unknown) => SmtpTransport;

export type CreateEmailSenderOptions = {
  fetch?: FetchLike;
  createSmtpTransport?: SmtpTransportFactory;
};

const defaultFetch: FetchLike = (input, init) => fetch(input, init);

export function createEmailSenderFromEnv(
  env: EnvSource,
  options: CreateEmailSenderOptions = {}
): EmailDeliveryResolution {
  const from = env.AUTH_EMAIL_FROM ?? env.EMAIL_FROM ?? env.SMTP_FROM;

  if (env.RESEND_API_KEY !== undefined && env.RESEND_API_KEY.length > 0) {
    if (from === undefined || from.length === 0) {
      return missingFrom("Resend");
    }

    return {
      reason: "resend_configured",
      sender: createResendEmailSender({
        apiKey: env.RESEND_API_KEY,
        from,
        fetch: options.fetch ?? defaultFetch
      })
    };
  }

  if (
    env.POSTMARK_SERVER_TOKEN !== undefined &&
    env.POSTMARK_SERVER_TOKEN.length > 0
  ) {
    if (from === undefined || from.length === 0) {
      return missingFrom("Postmark");
    }

    return {
      reason: "postmark_configured",
      sender: createPostmarkEmailSender({
        serverToken: env.POSTMARK_SERVER_TOKEN,
        from,
        fetch: options.fetch ?? defaultFetch
      })
    };
  }

  if (
    (env.SMTP_URL !== undefined && env.SMTP_URL.length > 0) ||
    (env.SMTP_HOST !== undefined && env.SMTP_HOST.length > 0)
  ) {
    if (from === undefined || from.length === 0) {
      return missingFrom("SMTP");
    }

    return {
      reason: "smtp_configured",
      sender: createSmtpEmailSender({
        from,
        env,
        createTransport:
          options.createSmtpTransport ??
          ((transportOptions) =>
            nodemailer.createTransport(
              transportOptions as Parameters<typeof nodemailer.createTransport>[0]
            ))
      })
    };
  }

  return {
    sender: null,
    reason: "email_provider_unconfigured"
  };
}

export function createResendEmailSender({
  apiKey,
  from,
  fetch
}: {
  apiKey: string;
  from: string;
  fetch: FetchLike;
}): AuthEmailSender {
  return {
    async send(message) {
      const response = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          authorization: `Bearer ${apiKey}`,
          "content-type": "application/json"
        },
        body: JSON.stringify({
          from,
          to: message.to,
          subject: message.subject,
          text: message.text,
          html: message.html
        })
      });
      await assertEmailProviderResponse("Resend", response);
    }
  };
}

export function createPostmarkEmailSender({
  serverToken,
  from,
  fetch
}: {
  serverToken: string;
  from: string;
  fetch: FetchLike;
}): AuthEmailSender {
  return {
    async send(message) {
      const response = await fetch("https://api.postmarkapp.com/email", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-postmark-server-token": serverToken
        },
        body: JSON.stringify({
          From: from,
          To: message.to,
          Subject: message.subject,
          TextBody: message.text,
          HtmlBody: message.html
        })
      });
      await assertEmailProviderResponse("Postmark", response);
    }
  };
}

function createSmtpEmailSender({
  from,
  env,
  createTransport
}: {
  from: string;
  env: EnvSource;
  createTransport: SmtpTransportFactory;
}): AuthEmailSender {
  const transport = createTransport(
    env.SMTP_URL !== undefined && env.SMTP_URL.length > 0
      ? env.SMTP_URL
      : {
          host: env.SMTP_HOST,
          port: parsePort(env.SMTP_PORT),
          secure: parseBoolean(env.SMTP_SECURE),
          auth:
            env.SMTP_USER !== undefined && env.SMTP_PASSWORD !== undefined
              ? {
                  user: env.SMTP_USER,
                  pass: env.SMTP_PASSWORD
                }
              : undefined
        }
  );

  return {
    async send(message) {
      await transport.sendMail({
        from,
        to: message.to,
        subject: message.subject,
        text: message.text,
        html: message.html
      });
    }
  };
}

export function buildAuthEmailMessage({
  purpose,
  to,
  url,
  token
}: {
  purpose: AuthEmailPurpose;
  to: string;
  url: string;
  token: string;
}): AuthEmailMessage {
  const isVerification = purpose === "email-verification";
  const subject = isVerification
    ? "Verify your Perennia email"
    : "Reset your Perennia password";
  const action = isVerification ? "verify your email" : "reset your password";
  const text = `Use this link to ${action}: ${url}`;

  return {
    purpose,
    to,
    subject,
    text,
    html: `<p>Use this link to ${action}: <a href="${escapeHtml(url)}">${escapeHtml(
      url
    )}</a></p>`,
    url,
    token
  };
}

async function assertEmailProviderResponse(provider: string, response: Response) {
  if (response.ok) {
    return;
  }

  const body = await response.text().catch(() => "");
  throw new Error(
    `${provider} email request failed with ${response.status}: ${body}`
  );
}

function missingFrom(provider: string): EmailDeliveryResolution {
  return {
    sender: null,
    reason: `${provider.toLowerCase()}_from_unconfigured`
  };
}

function parsePort(value: string | undefined) {
  if (value === undefined || value.length === 0) {
    return undefined;
  }

  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < 1 || parsed > 65535) {
    throw new Error(`Invalid SMTP_PORT: ${value}`);
  }

  return parsed;
}

function parseBoolean(value: string | undefined) {
  if (value === undefined || value.length === 0) {
    return undefined;
  }

  return ["1", "true", "yes"].includes(value.toLowerCase());
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
