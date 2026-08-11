import assert from "node:assert/strict";
import test from "node:test";

import { createEmailSenderFromEnv } from "../src/auth/email.ts";

const message = {
  purpose: "email-verification",
  to: "user@example.com",
  subject: "Subject",
  text: "Plain text",
  html: "<p>HTML</p>",
  url: "https://example.com/verify?token=token",
  token: "token"
};

test("Resend email sender posts transactional email payloads", async () => {
  const calls = [];
  const resolution = createEmailSenderFromEnv(
    {
      RESEND_API_KEY: "resend-key",
      AUTH_EMAIL_FROM: "Perennia <noreply@example.com>"
    },
    {
      async fetch(input, init) {
        calls.push({ input, init });
        return new Response("{}", { status: 200 });
      }
    }
  );

  assert.equal(resolution.reason, "resend_configured");
  assert.notEqual(resolution.sender, null);

  await resolution.sender.send(message);

  assert.equal(calls.length, 1);
  assert.equal(calls[0].input, "https://api.resend.com/emails");
  assert.equal(calls[0].init.headers.authorization, "Bearer resend-key");
  assert.deepEqual(JSON.parse(calls[0].init.body), {
    from: "Perennia <noreply@example.com>",
    to: "user@example.com",
    subject: "Subject",
    text: "Plain text",
    html: "<p>HTML</p>"
  });
});

test("Postmark email sender posts transactional email payloads", async () => {
  const calls = [];
  const resolution = createEmailSenderFromEnv(
    {
      POSTMARK_SERVER_TOKEN: "postmark-token",
      AUTH_EMAIL_FROM: "noreply@example.com"
    },
    {
      async fetch(input, init) {
        calls.push({ input, init });
        return new Response("{}", { status: 200 });
      }
    }
  );

  assert.equal(resolution.reason, "postmark_configured");
  assert.notEqual(resolution.sender, null);

  await resolution.sender.send(message);

  assert.equal(calls.length, 1);
  assert.equal(calls[0].input, "https://api.postmarkapp.com/email");
  assert.equal(
    calls[0].init.headers["x-postmark-server-token"],
    "postmark-token"
  );
  assert.deepEqual(JSON.parse(calls[0].init.body), {
    From: "noreply@example.com",
    To: "user@example.com",
    Subject: "Subject",
    TextBody: "Plain text",
    HtmlBody: "<p>HTML</p>"
  });
});

test("SMTP email sender uses self-host transport settings", async () => {
  const sent = [];
  const transportOptions = [];
  const resolution = createEmailSenderFromEnv(
    {
      SMTP_HOST: "smtp.example.com",
      SMTP_PORT: "587",
      SMTP_USER: "smtp-user",
      SMTP_PASSWORD: "smtp-password",
      SMTP_SECURE: "false",
      AUTH_EMAIL_FROM: "noreply@example.com"
    },
    {
      createSmtpTransport(options) {
        transportOptions.push(options);
        return {
          async sendMail(payload) {
            sent.push(payload);
          }
        };
      }
    }
  );

  assert.equal(resolution.reason, "smtp_configured");
  assert.notEqual(resolution.sender, null);

  await resolution.sender.send(message);

  assert.deepEqual(transportOptions, [
    {
      host: "smtp.example.com",
      port: 587,
      secure: false,
      auth: {
        user: "smtp-user",
        pass: "smtp-password"
      }
    }
  ]);
  assert.deepEqual(sent, [
    {
      from: "noreply@example.com",
      to: "user@example.com",
      subject: "Subject",
      text: "Plain text",
      html: "<p>HTML</p>"
    }
  ]);
});

test("email sender resolution is disabled without provider configuration", () => {
  const resolution = createEmailSenderFromEnv({});

  assert.equal(resolution.sender, null);
  assert.equal(resolution.reason, "email_provider_unconfigured");
});
