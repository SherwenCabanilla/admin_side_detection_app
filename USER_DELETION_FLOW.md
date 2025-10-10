# User Deletion Flow Diagram

## Complete Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         ADMIN PANEL UI                          │
│                  (user_management.dart)                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 1. Admin clicks "Delete User"
                              ▼
                    ┌───────────────────┐
                    │ Confirmation      │
                    │ Dialog            │
                    └───────────────────┘
                              │
                              │ 2. Confirmed
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       FLUTTER SERVICE                           │
│                    (user_store.dart)                            │
│                                                                 │
│  UserStore.deleteUser(userId)                                   │
│    │                                                            │
│    ├─► 3. Call Cloud Function                                  │
│    │   _functions.httpsCallable('deleteUserAccount')           │
│    │                                                            │
│    └─► Fallback: Direct Firestore delete (if CF fails)         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 4. HTTPS Callable Request
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      CLOUD FUNCTION                             │
│              deleteUserAccount (index.js)                       │
│                                                                 │
│  5. Verify Authentication                                       │
│     ├─► Check request.auth exists                              │
│     └─► Verify caller is in 'admins' collection                │
│                                                                 │
│  6. Get User Data                                               │
│     └─► Fetch user document for logging                        │
│                                                                 │
│  7. Delete Firebase Auth Account                               │
│     ├─► admin.auth().deleteUser(userId)                        │
│     └─► Handle "user-not-found" gracefully                     │
│                                                                 │
│  8. Delete Firestore Document                                  │
│     └─► admin.firestore().collection('users').doc().delete()   │
│                                                                 │
│  9. Delete Associated Scan Requests                            │
│     ├─► Query scan_requests where userId == userId             │
│     └─► Delete all matching documents                          │
│                                                                 │
│  10. Return Success Response                                    │
│      └─► { success: true, message: "...", deletedScanRequests }│
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 11. Response
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       FLUTTER SERVICE                           │
│                                                                 │
│  12. Handle Response                                            │
│      ├─► Log success message                                   │
│      └─► Return true to UI                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ 13. Success
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         ADMIN PANEL UI                          │
│                                                                 │
│  14. Update UI                                                  │
│      ├─► Create activity log                                   │
│      ├─► Show success message                                  │
│      └─► Refresh user list                                     │
└─────────────────────────────────────────────────────────────────┘
```

## Data Deletion Sequence

```
USER DELETION
    │
    ├─► 1. FIREBASE AUTHENTICATION
    │   │
    │   └─► DELETE /auth/users/{userId}
    │       ├─► Invalidates all tokens
    │       ├─► Prevents future sign-ins
    │       └─► Removes from Auth console
    │
    ├─► 2. FIRESTORE USER DOCUMENT
    │   │
    │   └─► DELETE /users/{userId}
    │       ├─► Removes user profile data
    │       ├─► Deletes: name, email, phone, etc.
    │       └─► Removes from admin user list
    │
    └─► 3. FIRESTORE SCAN REQUESTS
        │
        └─► DELETE /scan_requests (where userId == userId)
            ├─► Deletes all user's scan history
            ├─► Removes disease detection records
            └─► Cleans up orphaned data
```

## Security Flow

```
SECURITY VERIFICATION
    │
    ├─► 1. AUTHENTICATION CHECK
    │   │
    │   ├─► request.auth exists?
    │   │   ├─► YES ──► Continue
    │   │   └─► NO  ──► Error: "Authentication required"
    │   │
    │   └─► Get caller UID
    │
    ├─► 2. ADMIN AUTHORIZATION
    │   │
    │   ├─► Check /admins/{callerUid} exists?
    │   │   ├─► YES ──► Continue
    │   │   └─► NO  ──► Error: "Unauthorized: Only admins can delete"
    │   │
    │   └─► Admin verified ✓
    │
    └─► 3. DELETION ALLOWED
        └─► Proceed with user deletion
```

## Error Handling Flow

```
CLOUD FUNCTION CALL
    │
    ├─► SUCCESS PATH
    │   ├─► Auth deleted
    │   ├─► Firestore deleted
    │   ├─► Scan requests deleted
    │   └─► Return success
    │
    ├─► AUTH NOT FOUND PATH
    │   ├─► Log: "Auth account not found"
    │   ├─► Continue (not a critical error)
    │   ├─► Firestore deleted
    │   ├─► Scan requests deleted
    │   └─► Return success
    │
    ├─► CLOUD FUNCTION ERROR PATH
    │   ├─► Error caught in Flutter
    │   ├─► Log error
    │   ├─► Attempt fallback
    │   │   └─► Direct Firestore delete
    │   └─► Log warning: "Auth may still exist"
    │
    └─► COMPLETE FAILURE PATH
        ├─► All attempts failed
        ├─► Return false
        └─► Show error to admin
```

## Before vs After

### BEFORE (Old Implementation)

```
Admin clicks Delete
    │
    └─► Firestore.delete('/users/{userId}')
        │
        ├─► ✅ User document deleted
        ├─► ❌ Auth account still exists
        ├─► ❌ Scan requests still exist
        └─► ❌ User can still sign in!
```

### AFTER (New Implementation)

```
Admin clicks Delete
    │
    └─► Cloud Function: deleteUserAccount(userId)
        │
        ├─► ✅ Auth account deleted
        ├─► ✅ User document deleted
        ├─► ✅ Scan requests deleted
        └─► ✅ User completely removed!
```

## Component Interaction

```
┌──────────────┐
│   Flutter    │
│  Admin App   │
└──────┬───────┘
       │ HTTPS Callable
       │ (authenticated)
       ▼
┌──────────────────────┐
│  Cloud Function      │
│  (Server-side)       │
│                      │
│  - Admin SDK         │
│  - Full privileges   │
│  - Secure execution  │
└──┬──────────┬────────┘
   │          │
   │          └─────────────────┐
   │                            │
   ▼                            ▼
┌──────────────┐      ┌──────────────────┐
│  Firebase    │      │   Firestore      │
│    Auth      │      │                  │
│              │      │  - users/        │
│ Delete User  │      │  - scan_requests/│
└──────────────┘      └──────────────────┘
```

## Deployment Flow

```
1. CODE CHANGES
   ├─► functions/index.js (Cloud Function)
   ├─► lib/models/user_store.dart (Flutter service)
   └─► pubspec.yaml (Add cloud_functions package)

2. INSTALL DEPENDENCIES
   ├─► cd functions && npm install
   └─► flutter pub get

3. DEPLOY CLOUD FUNCTION
   └─► firebase deploy --only functions:deleteUserAccount

4. DEPLOY WEB APP (if needed)
   ├─► flutter build web
   └─► firebase deploy --only hosting

5. TESTING
   ├─► Create test user
   ├─► Delete from admin panel
   └─► Verify in Firebase Console
```

This implementation ensures complete, secure, and reliable user deletion! 🎯
