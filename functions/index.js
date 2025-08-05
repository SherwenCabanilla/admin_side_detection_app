const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
admin.initializeApp();

const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: functions.config().gmail.email,
    pass: functions.config().gmail.password,
  },
});

exports.notifyAdminOnUserRegister = functions.firestore
  .document("users/{userId}")
  .onCreate((snap, context) => {
    const newUser = snap.data();
    const mailOptions = {
      from: `"App Notification" <${functions.config().gmail.email}>`,
      to: "cabanilla.sherwen@dnsc.edu.ph", // <-- put your admin email here
      subject: "New User Registration",
      text: `A new user has registered:\n\nName: ${
        newUser.fullName || ""
      }\nEmail: ${newUser.email || ""}`,
    };
    return transporter.sendMail(mailOptions);
  });
