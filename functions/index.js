const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
admin.initializeApp();

// Transporter will be created inside the handler to avoid startup issues

// v2: define secrets for Gmail creds (set via `firebase functions:secrets:set`)
const GMAIL_EMAIL = defineSecret("GMAIL_EMAIL");
const GMAIL_PASSWORD = defineSecret("GMAIL_PASSWORD");

exports.notifyAdminOnUserRegister = onDocumentCreated(
  {
    document: "users/{userId}",
    region: "us-central1",
    secrets: [GMAIL_EMAIL, GMAIL_PASSWORD],
  },
  async (event) => {
    const snap = event.data; // QueryDocumentSnapshot
    const newUser = snap ? snap.data() : {};
    console.log("notifyAdminOnUserRegister: triggered", {
      userId: event.params && event.params.userId,
      email: newUser && newUser.email,
      name: newUser && newUser.fullName,
    });

    // Fetch admin emails with notifications enabled
    const adminsSnap = await admin.firestore().collection("admins").get();
    console.log(
      "notifyAdminOnUserRegister: fetched admins (will filter by prefs/email in code)",
      { count: adminsSnap.size },
    );

    const recipientEmails = adminsSnap.docs
      .map((d) => d.data() || {})
      .filter((data) => {
        const pref = data.notificationPrefs && data.notificationPrefs.email;
        // Treat missing pref as enabled; explicitly false disables
        return pref === true || typeof pref === "undefined";
      })
      .map((data) => data.email)
      .filter((e) => typeof e === "string" && e.includes("@"));
    const uniqueRecipients = Array.from(new Set(recipientEmails));
    console.log(
      "notifyAdminOnUserRegister: recipient emails (unique)",
      uniqueRecipients,
    );

    if (uniqueRecipients.length === 0) {
      // No recipients to notify
      return null;
    }

    const gmailEmail = GMAIL_EMAIL.value();
    const gmailPassword = GMAIL_PASSWORD.value();

    if (!gmailEmail || !gmailPassword) {
      console.error(
        "Missing gmail config. Set functions:config gmail.email and gmail.password",
      );
      return null;
    }

    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: gmailEmail,
        pass: gmailPassword,
      },
    });

    const from = `"MangoSense Notifications" <${gmailEmail}>`;
    const subject = "New user registration received";
    const adminUrl = "https://mango-leaf-analyzer.web.app/";

    const userName = newUser.fullName || newUser.name || "";
    const userEmail = newUser.email || "";
    const userPhone = newUser.phoneNumber || newUser.phone || "";
    const userRole = newUser.role || "user";
    const userStatus = newUser.status || "pending";
    const userAddress = newUser.address || "";

    const text =
      "A new user has registered and is awaiting review:\n\n" +
      `Name: ${userName}\n` +
      `Email: ${userEmail}\n` +
      (userPhone ? `Phone: ${userPhone}\n` : "") +
      `Role: ${userRole}\n` +
      `Status: ${userStatus}\n` +
      (userAddress ? `Address: ${userAddress}\n` : "") +
      "\nPlease sign in to the admin dashboard to review and approve this user." +
      `\n\nAdmin Portal: ${adminUrl}` +
      "\nOn mobile: open your browser menu and choose 'Desktop site' for best results.";

    const html = `
      <div style="font-family: Arial, Helvetica, sans-serif; background:#f6f8fb; padding:24px;">
        <div style="max-width:620px; margin:0 auto; background:#ffffff; border-radius:8px; overflow:hidden; box-shadow:0 2px 8px rgba(16,24,40,.06);">
          <div style="background:#16a34a; color:#ffffff; padding:16px 20px;">
            <h2 style="margin:0; font-size:18px;">New user registration received</h2>
          </div>
          <div style="padding:20px; color:#101828;">
            <p style="margin:0 0 12px 0;">A new user has registered and is awaiting review.</p>
            <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%; border-collapse:collapse;">
              <tbody>
                <tr>
                  <td style="padding:8px 0; width:160px; color:#475467;">Name</td>
                  <td style="padding:8px 0; font-weight:600;">${userName}</td>
                </tr>
                <tr>
                  <td style="padding:8px 0; color:#475467;">Email</td>
                  <td style="padding:8px 0; font-weight:600;">${userEmail}</td>
                </tr>
                ${userPhone ? `<tr><td style="padding:8px 0; color:#475467;">Phone</td><td style="padding:8px 0; font-weight:600;">${userPhone}</td></tr>` : ""}
                <tr>
                  <td style="padding:8px 0; color:#475467;">Role</td>
                  <td style="padding:8px 0; font-weight:600;">${userRole}</td>
                </tr>
                <tr>
                  <td style="padding:8px 0; color:#475467;">Status</td>
                  <td style="padding:8px 0; font-weight:600;">${userStatus}</td>
                </tr>
                ${userAddress ? `<tr><td style="padding:8px 0; color:#475467;">Address</td><td style="padding:8px 0; font-weight:600;">${userAddress}</td></tr>` : ""}
              </tbody>
            </table>
            <p style="margin:16px 0 16px 0; color:#475467;">Please sign in to the admin dashboard to review and approve this user.</p>
            <p style="margin:0 0 16px 0;">
              <a href="${adminUrl}" style="display:inline-block; background:#16a34a; color:#ffffff; text-decoration:none; padding:10px 14px; border-radius:6px; font-weight:600;">Open Admin Portal</a>
            </p>
            <p style="margin:0; font-size:12px; color:#667085;">If opening on a mobile device, use your browser's <strong>Desktop site</strong> option for the best experience.</p>
          </div>
          <div style="background:#f9fafb; color:#667085; padding:12px 20px; font-size:12px;">
            <p style="margin:0;">This message was sent by MangoSense Admin.</p>
          </div>
        </div>
      </div>`;

    const mailOptions = {
      from,
      to: uniqueRecipients,
      subject,
      text,
      html,
      replyTo: userEmail || undefined,
    };
    try {
      console.log("notifyAdminOnUserRegister: sending email using", gmailEmail);
      const info = await transporter.sendMail(mailOptions);
      console.log("notifyAdminOnUserRegister: email sent", {
        messageId: info && info.messageId,
        accepted: info && info.accepted,
        rejected: info && info.rejected,
        response: info && info.response,
      });
      return null;
    } catch (err) {
      console.error("notifyAdminOnUserRegister: sendMail failed", err);
      throw err;
    }
  },
);
