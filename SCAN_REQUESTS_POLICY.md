# Scan Request Deletion Policy

## Overview

When a user is deleted from the system, this document explains what happens to their scan requests (disease detection records).

## Policy: **Delete ONLY Pending Scan Requests**

### What Gets Deleted ✅

- **Pending scan requests** (`status: "pending"`)
  - Requests that have NOT been reviewed by experts
  - Incomplete disease detection records
  - Awaiting expert analysis

### What Gets Preserved ✅

- **Completed/Reviewed scan requests** (`status: "completed"` or similar)
  - Requests that HAVE been reviewed by experts
  - Expert diagnosis and recommendations
  - Historical disease detection data

## Rationale

### Why Delete Pending Requests?

1. **Incomplete Data**: These requests were never completed
2. **No Expert Work**: No expert has invested time reviewing them
3. **Clean Deletion**: User is gone, their pending work can be removed
4. **No Historical Value**: Pending requests have no audit/research value

### Why Preserve Completed Requests?

1. **Expert Work**: Preserves the work completed by expert reviewers
2. **Historical Records**: Valuable for disease tracking and analytics
3. **Audit Trail**: Maintains system history and data integrity
4. **Research Value**: Completed diagnoses may be used for:
   - Disease outbreak tracking
   - Pattern analysis
   - Training data for future improvements
   - Statistical reports

## Implementation

### Cloud Function Logic

```javascript
// Delete ONLY pending scan requests
const scanRequestsSnapshot = await admin
  .firestore()
  .collection("scan_requests")
  .where("userId", "==", userId)
  .where("status", "==", "pending") // ← Key filter
  .get();
```

### What This Means

When you delete a user:

```
User: John Doe (ID: abc123)

Scan Requests:
├─ Request 1: Status = "pending"     → ❌ DELETED
├─ Request 2: Status = "pending"     → ❌ DELETED
├─ Request 3: Status = "completed"   → ✅ PRESERVED
├─ Request 4: Status = "reviewed"    → ✅ PRESERVED
└─ Request 5: Status = "pending"     → ❌ DELETED

Result: 3 pending requests deleted, 2 completed requests preserved
```

## Data After User Deletion

### Completed Scan Requests Still Show:

- Disease detected
- Expert diagnosis
- Expert recommendations
- Scan date and time
- Images (if stored)

### What's Missing:

- User's personal info (name, email, etc.) - deleted from `/users`
- User cannot sign in - Auth account deleted
- **Note**: You may want to keep a reference like "Deleted User" for display purposes

## Alternative Approaches (Not Implemented)

### Option 1: Delete ALL Scan Requests

**Pros:**

- Complete data removal
- GDPR compliance (right to be forgotten)

**Cons:**

- Loses valuable historical data
- Wastes expert work
- No disease tracking history

### Option 2: Delete NO Scan Requests

**Pros:**

- Complete historical record
- All expert work preserved

**Cons:**

- Orphaned data (references deleted user)
- Could confuse reporting
- Pending requests stay forever incomplete

### Option 3: Anonymize Instead of Delete (Future Enhancement)

**Pros:**

- Preserves all data for analytics
- Maintains data integrity
- GDPR compliant (personal info removed)

**Cons:**

- More complex implementation
- Requires updating all references
- Need to handle user ID references

## Future Considerations

### Potential Enhancements:

1. **Anonymize User Data**: Replace user info with "Anonymous User"
2. **Soft Delete**: Mark user as deleted but keep record
3. **Data Export**: Allow user to download their data before deletion
4. **Configurable Policy**: Let admin choose what to delete/preserve
5. **Time-Based Cleanup**: Auto-delete old pending requests after X days

## Current Behavior Summary

| Item                    | Deleted? | Reason                 |
| ----------------------- | -------- | ---------------------- |
| Firebase Auth Account   | ✅ Yes   | Prevent user login     |
| User Firestore Document | ✅ Yes   | Remove personal data   |
| Pending Scan Requests   | ✅ Yes   | Incomplete, no value   |
| Completed Scan Requests | ❌ No    | Historical/expert work |
| Activity Logs           | ❌ No    | Audit trail            |

## Display Considerations

### Orphaned Records Issue

After deleting a user, their completed scan requests will still exist but reference a deleted user ID.

**Recommended Solution:**
When displaying scan requests, check if user exists:

```dart
String getUserName(String userId) {
  final user = await getUser(userId);
  return user != null ? user.name : "Deleted User";
}
```

Or pre-process on deletion:

```javascript
// Before deleting user, update completed scans
await admin
  .firestore()
  .collection("scan_requests")
  .where("userId", "==", userId)
  .where("status", "==", "completed")
  .get()
  .then((snapshot) => {
    snapshot.docs.forEach((doc) => {
      doc.ref.update({
        userName: userData.fullName, // Store name
        userDeleted: true, // Flag as deleted
      });
    });
  });
```

## Testing

### Verify Correct Deletion:

1. Create test user
2. Create multiple scan requests:
   - Some with `status: "pending"`
   - Some with `status: "completed"`
3. Delete the user
4. Check Firestore:
   - ✅ Pending requests should be deleted
   - ✅ Completed requests should still exist

### Console Output:

```
deleteUserAccount: Deleted 3 pending scan requests for user abc123
Successfully deleted user: John Doe (john@example.com)
Note: 2 completed scan requests preserved for historical records
```

---

**This policy balances data privacy with data preservation, ensuring we respect user deletion while maintaining valuable historical records.** 📊
