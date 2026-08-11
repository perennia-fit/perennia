declare module "nodemailer" {
  export type SendMailOptions = {
    from: string;
    to: string;
    subject: string;
    text: string;
    html?: string;
  };

  export type Transporter = {
    sendMail(message: SendMailOptions): Promise<unknown>;
  };

  export function createTransport(options: unknown): Transporter;

  const nodemailer: {
    createTransport: typeof createTransport;
  };

  export default nodemailer;
}
