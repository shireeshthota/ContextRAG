-- Seed Data for Support Ticket System
-- Run after schema/support_tickets.sql
-- Same data as ContextRAG for comparison

-- =============================================================================
-- Products
-- =============================================================================
INSERT INTO support.products (name, category, description) VALUES
('CloudSync Pro', 'software', 'Enterprise file synchronization and backup solution'),
('SecureAuth', 'software', 'Multi-factor authentication and SSO platform'),
('DataVault', 'software', 'Encrypted data storage and sharing service'),
('API Gateway', 'service', 'API management and rate limiting service'),
('Support Portal', 'service', 'Customer support ticketing system');

-- =============================================================================
-- Customers
-- =============================================================================
INSERT INTO support.customers (email, name, company, plan_type) VALUES
('john.smith@acmecorp.com', 'John Smith', 'Acme Corporation', 'enterprise'),
('sarah.jones@techstart.io', 'Sarah Jones', 'TechStart Inc', 'pro'),
('mike.wilson@globalretail.com', 'Mike Wilson', 'Global Retail', 'enterprise'),
('lisa.chen@innovate.co', 'Lisa Chen', 'Innovate Co', 'pro'),
('david.brown@freelance.me', 'David Brown', NULL, 'free'),
('emma.garcia@bigbank.com', 'Emma Garcia', 'Big Bank Financial', 'enterprise'),
('alex.kumar@startup.xyz', 'Alex Kumar', 'Startup XYZ', 'pro'),
('rachel.kim@healthcare.org', 'Rachel Kim', 'Healthcare Plus', 'enterprise');

-- =============================================================================
-- Support Agents
-- =============================================================================
INSERT INTO support.agents (email, name, team) VALUES
('tom.agent@company.com', 'Tom Anderson', 'technical'),
('jane.agent@company.com', 'Jane Martinez', 'billing'),
('sam.agent@company.com', 'Sam Williams', 'technical'),
('kate.agent@company.com', 'Kate Johnson', 'general');

-- =============================================================================
-- Support Tickets
-- =============================================================================
INSERT INTO support.tickets (customer_id, agent_id, product_id, subject, description, status, priority, category) VALUES
-- Ticket 1: High priority authentication issue
(1, 1, 2, 'Unable to login with SSO after password change',
'After changing my corporate password, I can no longer login to SecureAuth using SSO. I get an error message saying "Authentication failed. Please contact your administrator." I have tried clearing cookies and using incognito mode but the issue persists. This is blocking my entire team from accessing our applications.',
'in_progress', 'high', 'technical'),

-- Ticket 2: Billing question
(2, 2, 1, 'Question about upgrading from Pro to Enterprise',
'We are considering upgrading our CloudSync Pro subscription from Pro to Enterprise. Can you provide details on: 1) Price difference, 2) Migration process, 3) Additional features we would get, 4) Any downtime during upgrade?',
'open', 'medium', 'billing'),

-- Ticket 3: Feature request
(3, NULL, 3, 'Request: Add folder-level sharing permissions',
'Currently DataVault only allows file-level sharing. For our use case, we need to share entire folders with different permission levels (view, edit, admin). This would greatly improve our workflow when onboarding new team members.',
'open', 'low', 'feature_request'),

-- Ticket 4: Urgent sync issue
(4, 1, 1, 'Files not syncing - data loss concern',
'CloudSync Pro has stopped syncing files since yesterday. The sync icon shows "paused" but I cannot resume it. I have critical work files that I need to sync urgently. The desktop app version is 4.2.1 on Windows 11.',
'in_progress', 'urgent', 'bug'),

-- Ticket 5: API rate limiting
(6, 3, 4, 'API rate limit exceeded unexpectedly',
'Our application is hitting rate limits on the API Gateway even though our dashboard shows we should have 50% capacity remaining. We are on the Enterprise plan with 10,000 requests/minute limit. This started happening after your last maintenance window.',
'waiting', 'high', 'technical'),

-- Ticket 6: Password reset not working
(5, NULL, 2, 'Password reset email not received',
'I requested a password reset for my SecureAuth account 3 hours ago but have not received the reset email. I have checked spam folder. My email is david.brown@freelance.me. Please help as I am locked out of my account.',
'open', 'medium', 'technical'),

-- Ticket 7: Resolved billing issue
(7, 2, 1, 'Double charged for monthly subscription',
'I noticed two charges of $49.99 on my credit card statement for March. Can you please refund the duplicate charge? Transaction IDs: TXN-2024-001234 and TXN-2024-001235.',
'resolved', 'medium', 'billing'),

-- Ticket 8: Integration question
(8, 3, 4, 'How to integrate API Gateway with our legacy system',
'We need to integrate API Gateway with our existing on-premise legacy system. The legacy system uses SOAP and we need to convert to REST. Is there documentation or professional services available for this type of integration?',
'in_progress', 'medium', 'technical');

-- =============================================================================
-- Ticket Messages
-- =============================================================================
-- Messages for Ticket 1 (SSO issue)
INSERT INTO support.ticket_messages (ticket_id, sender_type, sender_id, message, is_internal) VALUES
(1, 'customer', 1, 'After changing my corporate password, I can no longer login to SecureAuth using SSO. I get an error message saying "Authentication failed. Please contact your administrator."', FALSE),
(1, 'agent', 1, 'Thank you for contacting support. I understand SSO is not working after your password change. Can you confirm which identity provider your company uses (Okta, Azure AD, etc)?', FALSE),
(1, 'customer', 1, 'We use Azure AD for SSO.', FALSE),
(1, 'agent', 1, 'Internal note: Checking Azure AD integration logs. Possible token cache issue.', TRUE),
(1, 'agent', 1, 'I see the issue. Your Azure AD session needs to be refreshed. Please try signing out of all Microsoft services, then clear browser cache, and try again.', FALSE);

-- Messages for Ticket 4 (Sync issue)
INSERT INTO support.ticket_messages (ticket_id, sender_type, sender_id, message, is_internal) VALUES
(4, 'customer', 4, 'Files not syncing - data loss concern. CloudSync Pro has stopped syncing files since yesterday.', FALSE),
(4, 'agent', 1, 'I am looking into this urgently. Can you check if there are any files with special characters in their names in your sync folder?', FALSE),
(4, 'customer', 4, 'Yes, I have several files with # and & in the names from a recent project.', FALSE),
(4, 'agent', 1, 'That is likely the cause. Version 4.2.1 has a known issue with special characters. Please rename those files temporarily and try syncing again. A patch is coming next week.', FALSE);

-- Messages for Ticket 7 (Resolved billing)
INSERT INTO support.ticket_messages (ticket_id, sender_type, sender_id, message, is_internal) VALUES
(7, 'customer', 7, 'I noticed two charges of $49.99 on my credit card for March.', FALSE),
(7, 'agent', 2, 'I apologize for this billing error. I have processed a refund for transaction TXN-2024-001235. You should see it within 3-5 business days.', FALSE),
(7, 'customer', 7, 'Thank you for the quick resolution!', FALSE);

-- =============================================================================
-- Knowledge Base Articles
-- =============================================================================
INSERT INTO support.kb_articles (title, content, category, tags, product_id) VALUES
-- Article 1: SSO Setup
(
'How to configure SSO with Azure AD',
'This guide explains how to set up Single Sign-On (SSO) with Azure Active Directory for SecureAuth.

## Prerequisites
- Azure AD Premium license
- SecureAuth Enterprise plan
- Admin access to both Azure AD and SecureAuth

## Steps
1. In Azure AD, go to Enterprise Applications and click New Application
2. Search for SecureAuth and select it from the gallery
3. Configure SAML settings with the following:
   - Entity ID: https://auth.secureauth.com/saml/YOUR_TENANT
   - Reply URL: https://auth.secureauth.com/saml/acs
4. Download the Federation Metadata XML
5. In SecureAuth admin, go to Identity Providers and upload the metadata
6. Test the connection with a non-admin user first

## Troubleshooting
- "Authentication failed" error: Check that the user exists in both systems
- Token errors: Ensure clocks are synchronized between systems
- Certificate errors: Verify the SAML certificate has not expired',
'how_to', ARRAY['sso', 'azure', 'saml', 'authentication'], 2),

-- Article 2: Sync troubleshooting
(
'Troubleshooting CloudSync Pro sync issues',
'If CloudSync Pro is not syncing your files, follow these troubleshooting steps.

## Common Causes
1. Special characters in file names (#, &, %, etc.)
2. File size exceeds plan limit
3. Network connectivity issues
4. Outdated desktop client
5. Insufficient storage quota

## Quick Fixes

### Check sync status
Right-click the CloudSync icon in your system tray and select "Sync Status" to see pending items.

### Restart sync
1. Click the CloudSync icon
2. Select "Pause Sync"
3. Wait 10 seconds
4. Select "Resume Sync"

### Clear cache
1. Close CloudSync completely
2. Navigate to %APPDATA%\CloudSync\cache
3. Delete all files in this folder
4. Restart CloudSync

### Update client
Ensure you are running the latest version. Go to Help > Check for Updates.

## Still having issues?
If these steps do not resolve your issue, please contact support with:
- Your CloudSync version number
- Operating system details
- Error messages (if any)
- List of files that fail to sync',
'troubleshooting', ARRAY['sync', 'files', 'desktop', 'troubleshooting'], 1),

-- Article 3: API Rate Limiting
(
'Understanding API Gateway rate limits',
'This article explains how rate limiting works in API Gateway and how to optimize your usage.

## Rate Limit Tiers
- Free: 100 requests/minute
- Pro: 1,000 requests/minute
- Enterprise: 10,000 requests/minute

## How Limits Work
Rate limits are calculated using a sliding window algorithm. The window is 60 seconds.

## Headers
Every API response includes rate limit headers:
- X-RateLimit-Limit: Your plan limit
- X-RateLimit-Remaining: Requests left in window
- X-RateLimit-Reset: Unix timestamp when window resets

## Best Practices
1. Cache responses when possible
2. Use batch endpoints for bulk operations
3. Implement exponential backoff on 429 errors
4. Monitor your usage dashboard

## Handling 429 Errors
When you exceed the limit, you receive HTTP 429 Too Many Requests. Wait for the time specified in Retry-After header before retrying.

## Requesting Higher Limits
Enterprise customers can request temporary limit increases for planned traffic spikes. Contact your account manager at least 48 hours in advance.',
'how_to', ARRAY['api', 'rate-limit', 'throttling', 'best-practices'], 4),

-- Article 4: Password Reset
(
'How to reset your SecureAuth password',
'Follow these steps if you need to reset your SecureAuth password.

## Self-Service Reset
1. Go to https://auth.secureauth.com/login
2. Click "Forgot Password?"
3. Enter your registered email address
4. Check your inbox for the reset link (check spam folder too)
5. Click the link within 24 hours
6. Create a new password meeting requirements

## Password Requirements
- Minimum 12 characters
- At least one uppercase letter
- At least one lowercase letter
- At least one number
- At least one special character

## Email Not Received?
- Check spam/junk folders
- Verify you entered the correct email
- Wait 15 minutes and try again
- Contact support if still not received

## Account Locked?
After 5 failed attempts, accounts are locked for 30 minutes. Wait or contact support for immediate unlock.

## SSO Users
If you login via SSO (company credentials), you must reset your password through your company identity provider, not SecureAuth.',
'how_to', ARRAY['password', 'reset', 'login', 'security'], 2),

-- Article 5: DataVault Sharing
(
'Sharing files and folders in DataVault',
'Learn how to share files securely with DataVault.

## Sharing Options
- View only: Recipients can view but not download
- Download: Recipients can view and download
- Edit: Recipients can modify files (Pro and Enterprise only)

## How to Share
1. Select the file or folder
2. Click the Share button
3. Enter recipient email addresses
4. Choose permission level
5. Optionally set expiration date
6. Click Send

## Share Links
You can also create shareable links:
1. Right-click the file
2. Select "Create Link"
3. Configure link settings (password, expiration)
4. Copy and distribute the link

## Revoking Access
To remove someone''s access:
1. Open file/folder properties
2. Go to Sharing tab
3. Find the user
4. Click Remove

## Folder Sharing (Enterprise only)
Enterprise customers can share entire folders. When you share a folder:
- All current files are shared
- New files added are automatically shared
- Subfolder permissions can be customized

Note: Folder-level sharing is not yet available for Pro plans. See our roadmap for updates.',
'how_to', ARRAY['sharing', 'permissions', 'collaboration', 'security'], 3);

-- Update ticket 7 resolved_at
UPDATE support.tickets SET resolved_at = NOW() - INTERVAL '1 day' WHERE id = 7;
