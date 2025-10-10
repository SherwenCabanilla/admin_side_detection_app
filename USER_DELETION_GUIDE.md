# User Deletion Implementation

## Overview

This document explains how user deletion works in the MangoSense Admin System, including both Firebase Authentication and Firestore data deletion.

## How It Works

### Previous Implementation ❌

- **Only deleted Firestore document** in the `users` collection
- **Did NOT delete Firebase Authentication account**
- Left orphaned authentication accounts that could still sign in
- Did NOT clean up associated scan requests

### Current Implementation ✅

- **Deletes Firebase Authentication account** (via Cloud Function)
- **Deletes Firestore document** in the `users` collection
- **Deletes ONLY pending scan requests** (preserves completed/reviewed scans)
- **Provides fallback mechanism** if Cloud Function fails
- **Secure**: Only authenticated admins can delete users

## Architecture

### Cloud Function: `deleteUserAccount`

Located in: `functions/index.js`

**Features:**

- Callable HTTPS function (v2)
- Requires admin authentication
- Handles both Auth and Firestore deletion
- Cleans up ONLY pending scan requests (preserves completed reviews)
- Gracefully handles missing Auth accounts
- Returns detailed results

**Security:**

- Verifies caller is authenticated
- Verifies caller is in `admins` collection
- Prevents unauthorized deletions

### Flutter Implementation

Located in: `lib/models/user_store.dart`

**Features:**

- Calls the `deleteUserAccount` Cloud Function
- Handles errors gracefully
- Provides fallback to Firestore-only deletion if Cloud Function fails
- Logs all operations for debugging

## User Flow

### When Admin Deletes a User:

1. **Admin clicks Delete** button in User Management
2. **Confirmation dialog** appears
3. **Cloud Function is called** with `userId`
4. **Cloud Function verifies** admin permissions
5. **Retrieves user data** for logging
6. **Deletes Firebase Auth account**
   - If account doesn't exist, logs warning and continues
7. **Deletes Firestore document**
8. **Finds and deletes ONLY pending scan requests** where `userId` matches
   - Completed/reviewed scans are preserved for historical records
9. **Returns success** with details:
   - User name and email
   - Number of pending scan requests deleted
10. **Activity log is created** in admin dashboard
11. **UI updates** to reflect deletion

### Fallback Mechanism:

If the Cloud Function fails (network issues, function not deployed, etc.):

- Attempts direct Firestore deletion
- Logs warning that Auth account may still exist
- Returns success if Firestore deletion succeeds

## What Gets Deleted

When a user is deleted, the following data is removed:

1. ✅ **Firebase Authentication Account**

   - User can no longer sign in
   - Auth token is invalidated

2. ✅ **Firestore User Document**

   - `/users/{userId}` document

3. ✅ **Pending Scan Requests Only**

   - Only documents in `/scan_requests` where `userId` matches AND `status == "pending"`
   - Completed/reviewed scans are preserved for historical/audit purposes

4. ❌ **NOT Deleted** (intentional):
   - Activity logs (preserved for audit trail)
   - Admin logs referencing the user
   - Completed/reviewed scan requests (preserved for expert work records)

## Deployment

### Deploy Cloud Function:

```bash
cd functions
npm install
firebase deploy --only functions:deleteUserAccount
```

### Install Flutter Dependencies:

```bash
flutter pub get
```

### Build and Deploy Admin Web App:

```bash
flutter build web
firebase deploy --only hosting
```

## Testing

### Test User Deletion:

1. Create a test user account (via mobile app)
2. Sign in to admin panel
3. Navigate to User Management
4. Click delete on the test user
5. Verify in Firebase Console:
   - Authentication: User should be removed
   - Firestore: User document should be removed
   - Firestore: Scan requests should be removed

### Check Logs:

```bash
firebase functions:log --only deleteUserAccount
```

## Security Considerations

1. **Admin-Only Access**: Only users in the `admins` collection can delete users
2. **Authentication Required**: Caller must be authenticated
3. **Audit Trail**: All deletions are logged in the activities collection
4. **Graceful Failure**: If Auth deletion fails, Firestore deletion still proceeds
5. **No Cascade Issues**: Deletes related data (scan requests) to prevent orphans

## Error Handling

### Common Errors:

**"Authentication required to delete users"**

- User is not signed in
- Solution: Ensure admin is authenticated

**"Unauthorized: Only admins can delete users"**

- Caller is not in admins collection
- Solution: Verify admin account exists in Firestore

**"auth/user-not-found"**

- Auth account already deleted or never existed
- Handled gracefully, continues with Firestore deletion

**Cloud Function timeout**

- Network issues or function not deployed
- Falls back to Firestore-only deletion

## Code References

### Cloud Function (functions/index.js):

```javascript
exports.deleteUserAccount = onCall(
  { region: "us-central1" },
  async (request) => {
    // Verify authentication and admin status
    // Delete from Firebase Auth
    // Delete from Firestore
    // Delete associated scan requests
    // Return success with details
  }
);
```

### Flutter Service (lib/models/user_store.dart):

```dart
static Future<bool> deleteUser(String userId) async {
  try {
    final callable = _functions.httpsCallable('deleteUserAccount');
    final result = await callable.call({'userId': userId});
    return result.data['success'] == true;
  } catch (e) {
    // Fallback to Firestore-only deletion
  }
}
```

## Future Enhancements

Potential improvements:

- [ ] Add batch user deletion
- [ ] Implement soft delete (archive instead of delete)
- [ ] Add user data export before deletion
- [ ] Send email notification when user is deleted
- [ ] Add undo functionality within time window
- [ ] Delete user-uploaded images from Storage

## Related Files

- `functions/index.js` - Cloud Function implementation
- `lib/models/user_store.dart` - Flutter service layer
- `lib/screens/user_management.dart` - User management UI
- `lib/shared/pending_approvals_card.dart` - Pending user approvals UI
- `pubspec.yaml` - Added cloud_functions package
