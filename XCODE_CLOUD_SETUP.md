# Xcode Cloud Setup for Lumina

## The Error You're Seeing
"Workflow cannot be saved. This workflow has no actions."

This happens when you create a new Xcode Cloud workflow but haven't added any steps yet.

## How to Fix It (Quick)

1. In Xcode, go to **Product > Xcode Cloud > Manage Workflows**.
2. Create a new workflow or edit the existing one.
3. In the workflow editor, click **"Add Action"** (big blue button).
4. Add at least one of these:
   - **Build** (recommended starting point)
   - **Test** (if you want to run LuminaTests + LuminaUITests)
   - **Analyze**
5. Configure the following:

### Recommended Minimal Configuration

**Primary Repository**: Your Lumina repo

**Default Branch**: `main` (or `master`)

**Actions** (add these):
- Build (for the "Lumina" scheme)
- (Optional but recommended) Test

**Scheme**: `Lumina`

**Xcode Version**: Latest or a specific recent version

**Environment Variables** (very important for this app):

You **must** add this as a **Secret** (not Plain text):

- **Name**: `XAI_API_KEY`
- **Type**: Secret
- **Value**: Your actual key (starts with `xai-`)

### Recommended way to add it (Updated - Scheme is now available):

Now that the "Lumina AI personal trainer" scheme has been pushed and is visible in Xcode Cloud, follow these exact steps:

1. Open your workflow in Xcode Cloud.
2. Click **Edit Workflow**.
3. Scroll down to the **Environment** section.
4. Click **Add Variable**.
5. Fill in exactly:
   - **Variable Name**: `XAI_API_KEY`
   - **Value**: Paste your full key (starts with `xai-`)
   - **Type**: **Secret** ← Critical
   - **Scope**: Workflow (recommended for now)
6. Click **Add**.

**Important**:
- After adding, you should see the variable listed with a lock icon and "Secret" label.
- The value will be shown as `••••••••` — this is correct.
- Do **not** add it as Plain Text.

**Best practice**: Always test the key locally first using:
```bash
./test_xai_key.sh --scenario low_energy_evening_walk
```
before adding it to Xcode Cloud. This has saved a lot of time in previous attempts.

### Exact steps to add the secret correctly (this is the most common place people get stuck):

1. In the workflow editor, scroll down to the **Environment** section.
2. Click **"Add Variable"**.
3. In the popup:
   - Enter `XAI_API_KEY` as the **Variable Name**.
   - **Very important**: Change the type from "Plain text" to **Secret**.
   - Paste your full API key into the **Value** field (do not add quotes, do not add extra spaces).
4. Click **Add**.
5. After adding it, you should see it listed with a "Secret" label (it will show dots or "••••••" instead of the actual key).

**Pro tip:** Always test the key locally first using `./test_xai_key.sh` (or with `--scenario`) before adding it to Xcode Cloud. This saves a lot of debugging time.

This error ("Failed to save the environment variable XAI_API_KEY due to invalid value") almost always means:
- You left the type as "Plain text" instead of "Secret", **or**
- The value field was left empty, **or**
- You accidentally included quotes or whitespace when pasting the key.

After fixing the secret, try saving the workflow again.

This key is read by the app like this:
```swift
ProcessInfo.processInfo.environment["XAI_API_KEY"]
```

Without it, all the smart AI coach features will fall back to local logic only.

**App Store Connect / Signing**:
- For internal testing: Use "Automatically manage signing" with your team.
- You will likely need to grant Xcode Cloud access to your Developer Portal and App Store Connect.

## Custom Scripts

This project includes a starter `ci_scripts/ci_post_clone.sh`.

You can expand it later for:
- Installing additional tools
- Pre-processing localization files
- Running SwiftLint / SwiftFormat before build

## Next Recommended Workflow

Once the basic "Build" workflow works, consider creating a second workflow:
- Name: "Lumina - Pull Request"
- Trigger: On Pull Request
- Actions: Build + Test

## Notes Specific to Lumina

- The app uses **HealthKit**, **Live Activities**, **App Groups** (`group.SA.Lumina`), **Widgets**, and **CloudKit**.
- Xcode Cloud builds run in a sandbox. Some capabilities (especially HealthKit simulation and Live Activities) have limited support.
- Widget extension + App Group will require proper entitlement configuration in the workflow if you add a Widget target later.

## Testing Your xAI API Key Locally

Before putting the key into Xcode Cloud, test it locally using the improved test script:

```bash
# Option 1: Export the key first
export XAI_API_KEY="xai-your-actual-key-here"
cd Lumina
./test_xai_key.sh

# Option 2: Pass a custom question
./test_xai_key.sh "How should I adjust my training if I'm feeling very sore?"

# Option 3: One-liner
XAI_API_KEY="xai-..." ./test_xai_key.sh "Explain progressive overload simply."
```

This script uses the **exact same API format** as the Lumina app (`/v1/chat/completions` + `grok-3-latest`).

## Still Stuck?

After adding at least one "Build" or "Test" action, the "Save" button should become enabled.

If you continue getting errors after adding actions, the issue is usually:
- No scheme selected
- The selected scheme has no buildable targets for the platform
- Missing repository access permissions

Let me know what exact error you see after adding a Build action.
