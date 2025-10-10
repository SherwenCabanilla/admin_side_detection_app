# Quick Deployment Guide - User Deletion Feature

## ⚡ Quick Start (5 Minutes)

### Step 1: Install Dependencies

```bash
# Install Flutter package
flutter pub get

# Install Cloud Functions dependencies
cd functions
npm install
cd ..
```

### Step 2: Deploy Cloud Function

```bash
# Deploy the deleteUserAccount function
firebase deploy --only functions:deleteUserAccount
```

### Step 3: Test

1. Open admin panel in browser
2. Go to User Management
3. Try deleting a test user
4. Verify in Firebase Console that:
   - Auth account is deleted ✓
   - Firestore document is deleted ✓
   - Scan requests are deleted ✓

## 🔍 Verify Deployment

### Check Function is Live

```bash
firebase functions:list
```

Should show: `deleteUserAccount (us-central1)`

### View Function Logs

```bash
firebase functions:log --only deleteUserAccount
```

### Test in Firebase Console

1. Go to: Firebase Console → Functions
2. Find: `deleteUserAccount`
3. Status should be: ✅ Healthy

## 📋 What Was Changed

### Files Modified:

- ✅ `functions/index.js` - Added deleteUserAccount Cloud Function
- ✅ `lib/models/user_store.dart` - Updated deleteUser method
- ✅ `pubspec.yaml` - Added cloud_functions package

### Files Created:

- ✅ `USER_DELETION_GUIDE.md` - Complete implementation guide
- ✅ `IMPLEMENTATION_SUMMARY.md` - Summary of changes
- ✅ `USER_DELETION_FLOW.md` - Visual flow diagrams
- ✅ `QUICK_DEPLOY.md` - This file

## 🧪 Testing Checklist

- [ ] Run `flutter pub get`
- [ ] Run `cd functions && npm install`
- [ ] Deploy function: `firebase deploy --only functions:deleteUserAccount`
- [ ] Open admin panel
- [ ] Delete a test user
- [ ] Check Firebase Console → Authentication (user removed?)
- [ ] Check Firebase Console → Firestore → users (document removed?)
- [ ] Check Firebase Console → Firestore → scan_requests (user's requests removed?)
- [ ] Check activity log shows deletion

## ⚠️ Important Notes

1. **Region**: Cloud Function is deployed to `us-central1`
2. **Security**: Only authenticated admins can delete users
3. **Fallback**: If Cloud Function fails, Firestore-only deletion is attempted
4. **Logging**: All deletions are logged to activities collection

## 🔧 Troubleshooting

### Error: "Cloud Functions not found"

**Solution**: Run `firebase deploy --only functions:deleteUserAccount`

### Error: "Authentication required"

**Solution**: Ensure you're signed in as admin

### Error: "Unauthorized: Only admins can delete"

**Solution**: Verify your account exists in `/admins` collection

### Cloud Function times out

**Solution**: Check Firebase Console → Functions → Logs for errors

### Fallback message appears

**Symptom**: "WARNING: Firebase Auth account may still exist"
**Cause**: Cloud Function failed, used Firestore-only deletion
**Solution**: Deploy the Cloud Function properly

## 📊 Expected Behavior

### When Deleting a User:

**Console Output (Flutter):**

```
Deleting user abc123 (Auth + Firestore)...
Successfully deleted user: John Doe (john@example.com)
Deleted 5 associated scan requests
```

**Console Output (Cloud Function):**

```
deleteUserAccount: Deleting user abc123 by admin xyz789
deleteUserAccount: Successfully deleted auth account for abc123
deleteUserAccount: Successfully deleted Firestore doc for abc123
deleteUserAccount: Deleted 5 scan requests for user abc123
```

**User Sees:**

```
✅ User deleted successfully
[Activity log shows: "Deleted user - John Doe"]
```

## 🚀 Optional: Rebuild Web App

If you want to deploy the updated web app:

```bash
# Build for web
flutter build web

# Deploy to Firebase Hosting
firebase deploy --only hosting
```

## 📞 Need Help?

1. Check `USER_DELETION_GUIDE.md` for detailed documentation
2. Check `USER_DELETION_FLOW.md` for visual diagrams
3. Check function logs: `firebase functions:log --only deleteUserAccount`
4. Check Firebase Console → Functions for status

---

## Summary

You've successfully implemented proper user deletion that:

- ✅ Deletes Firebase Authentication account
- ✅ Deletes Firestore user document
- ✅ Deletes all associated scan requests
- ✅ Provides secure admin-only access
- ✅ Includes fallback mechanism
- ✅ Logs all operations

**This is best practice for Firebase user management!** 🎉
