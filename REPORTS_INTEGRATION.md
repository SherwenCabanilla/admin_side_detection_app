# Reports Page - Real Data Integration

## Overview

The reports page has been updated to use real data from Firestore instead of dummy data. This integration focuses on the disease card part and provides a foundation for expanding to other sections.

## Changes Made

### 1. New Service: `ScanRequestsService`

- **Location**: `lib/services/scan_requests_service.dart`
- **Purpose**: Handles all Firestore operations for scan requests data
- **Key Methods**:
  - `getScanRequests()`: Fetches all scan requests from Firestore
  - `getDiseaseStats(timeRange)`: Gets disease statistics for a specific time range
  - `getReportsTrend(timeRange)`: Gets reports trend data for a specific time range
  - `getTotalReportsCount()`: Gets total number of reports
  - `getPendingReportsCount()`: Gets number of pending reports
  - `getAverageResponseTime(timeRange)`: Calculates average response time

### 2. Updated Reports Page

- **Location**: `lib/screens/reports.dart`
- **Changes**:
  - Replaced dummy data with real Firestore data
  - Added loading states
  - Added error handling with fallback data
  - Integrated time range filtering
  - Added sample data generation functionality

### 3. Sample Data Generator

- **Location**: `lib/utils/sample_data_generator.dart`
- **Purpose**: Generates sample scan requests data for testing
- **Features**:
  - `generateSampleScanRequests()`: Creates 8 sample scan requests with various diseases
  - `clearSampleData()`: Removes all sample data from Firestore

### 4. Updated Components

- **TotalReportsCard**: Now accepts `totalReports` parameter
- **PendingApprovalsCard**: Now accepts `pendingCount` parameter
- **DiseaseDistributionChart**: Now uses real data and supports time range changes

## Data Structure

### Scan Request Document Structure

```json
{
  "userId": "USER_001",
  "userName": "Maria Santos",
  "status": "completed",
  "createdAt": "Timestamp",
  "reviewedAt": "Timestamp",
  "diseaseSummary": [
    {
      "name": "Anthracnose",
      "count": 2
    },
    {
      "name": "Healthy",
      "count": 1
    }
  ]
}
```

### Disease Statistics Structure

```json
{
  "name": "Anthracnose",
  "count": 156,
  "percentage": 0.25,
  "type": "disease"
}
```

## Features

### 1. Real-time Data Loading

- Automatically loads data from Firestore on page load
- Shows loading indicators while fetching data
- Handles empty data states gracefully

### 2. Time Range Filtering

- Supports multiple time ranges: 1 Day, Last 7 Days, Last 30 Days, etc.
- Dynamically updates charts and statistics based on selected range
- Maintains consistency across all data displays

### 3. Sample Data Management

- **Generate Sample Data**: Creates realistic test data
- **Clear Sample Data**: Removes test data
- Useful for development and testing

### 4. Error Handling

- Graceful fallbacks when data is unavailable
- Console logging for debugging
- User-friendly error messages

## Usage

### 1. Generate Sample Data

1. Navigate to the Reports page
2. Click "Generate Sample Data" button
3. Wait for confirmation message
4. Data will automatically refresh

### 2. View Real Data

1. The page automatically loads real data from Firestore
2. Use the time range dropdown to filter data
3. Charts and statistics update automatically

### 3. Clear Sample Data

1. Click "Clear Sample Data" button
2. Wait for confirmation message
3. Data will be removed from Firestore

## Supported Diseases

The system recognizes the following diseases:

- Anthracnose
- Bacterial Blackspot
- Powdery Mildew
- Dieback
- Healthy

**Note**: Tip Burn is excluded as it's a scanning feature in the mobile app, not a disease.

## Time Ranges

- 1 Day
- Last 7 Days
- Last 30 Days
- Last 60 Days
- Last 90 Days
- Last Year

## Next Steps

1. **Expand to other sections**: Apply similar real data integration to user management, expert management, etc.
2. **Add more analytics**: Include trend analysis, seasonal patterns, etc.
3. **Real-time updates**: Implement real-time listeners for live data updates
4. **Export functionality**: Add PDF generation with real data
5. **Advanced filtering**: Add more granular filtering options

## Testing

- Use the sample data generator to create test scenarios
- Test different time ranges to ensure proper filtering
- Verify error handling with network issues
- Test with empty Firestore collections
