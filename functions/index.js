const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onCall } = require("firebase-functions/v2/https");
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

/**
 * Cloud Function to delete a user account
 * Deletes both the Firebase Authentication account and Firestore document
 * Can only be called by authenticated admin users
 */
exports.deleteUserAccount = onCall(
  {
    region: "us-central1",
  },
  async (request) => {
    // Verify the caller is authenticated
    if (!request.auth) {
      throw new Error("Authentication required to delete users");
    }

    // Verify the caller is an admin
    const callerUid = request.auth.uid;
    const adminDoc = await admin
      .firestore()
      .collection("admins")
      .doc(callerUid)
      .get();

    if (!adminDoc.exists) {
      throw new Error("Unauthorized: Only admins can delete users");
    }

    const { userId } = request.data;

    if (!userId) {
      throw new Error("userId is required");
    }

    console.log(
      `deleteUserAccount: Deleting user ${userId} by admin ${callerUid}`,
    );

    try {
      // First, get the user document to retrieve the email for logging
      const userDoc = await admin
        .firestore()
        .collection("users")
        .doc(userId)
        .get();

      const userData = userDoc.exists ? userDoc.data() : null;
      const userEmail = (userData && userData.email) || "unknown";
      const userName =
        (userData && (userData.fullName || userData.name)) || "unknown";

      // Delete from Firebase Authentication
      try {
        await admin.auth().deleteUser(userId);
        console.log(
          `deleteUserAccount: Successfully deleted auth account for ${userId}`,
        );
      } catch (authError) {
        // If auth user doesn't exist, log it but continue to delete Firestore doc
        if (authError.code === "auth/user-not-found") {
          console.log(
            `deleteUserAccount: Auth account not found for ${userId}, continuing to delete Firestore doc`,
          );
        } else {
          throw authError;
        }
      }

      // Delete from Firestore
      await admin.firestore().collection("users").doc(userId).delete();
      console.log(
        `deleteUserAccount: Successfully deleted Firestore doc for ${userId}`,
      );

      // Delete ONLY pending scan requests
      // Completed/reviewed scans are preserved for historical records
      const scanRequestsSnapshot = await admin
        .firestore()
        .collection("scan_requests")
        .where("userId", "==", userId)
        .where("status", "==", "pending")
        .get();

      const deletePromises = scanRequestsSnapshot.docs.map((doc) =>
        doc.ref.delete(),
      );
      await Promise.all(deletePromises);
      console.log(
        `deleteUserAccount: Deleted ${deletePromises.length} pending scan requests for user ${userId}`,
      );

      return {
        success: true,
        message: `Successfully deleted user ${userName} (${userEmail})`,
        deletedPendingScanRequests: deletePromises.length,
      };
    } catch (error) {
      console.error(`deleteUserAccount: Error deleting user ${userId}`, error);
      throw new Error(`Failed to delete user: ${error.message}`);
    }
  },
);
