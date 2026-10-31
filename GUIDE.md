# FOLK Guide app — GUIDE

*A complete guide for a future developer or AI. Written 2026-10-31. It describes the apps, the server and the rules they obey. It contains **no secret value**; it says where each secret lives and how to replace it.*

**Contents:** 1 What this app is for · 2 The platform (roles, sign-in, Firestore, rules, Cloud Functions, hosting) · 3 Data rules and invariants · 4 Credentials and secrets · 5 Development setup · 6 Deploying · 7 Release process · 8 Adding features safely · 9 Operations and troubleshooting · 10 This app's screens, features and rules.

Related documents: `functions/HANDOVER.md` (a dated log of every server change and why), `functions/AGENT_CAPABILITIES.md` (everything the Guide assistant can do, generated), `functions/FOLK_APP_FAQ.md` (what the assistants tell users about the app), the app's `README.md`.

## 1. What this app is for

**FOLK Surat** is a mentorship programme for college students (hostel, local and ashram residents). This **Guide app** (package `org.folksurat.guides`, also a website at https://folk-guides.web.app) is the mentors' tool. The people who use it: the **HOD** (head of department: sees everything, manages admins, the AI budget and targets), **Guides**, **Male Enablers** and **Female Enablers** (see §2.1 for who sees whom; girls are only ever seen by Female Enablers and HODs). With it a mentor sees his students (Surrender %, sadhana, books, doubts, worries), gets a **plan for the day and the week** that the server builds, records interactions and meetings, runs **targets** (chanting, reading, FOLK residents), a calendar, trips, competitions, books and the Service Bank, and talks to an **AI assistant** that can read and change all of it with his confirmation. The students' companion is the **Student app**. Everything is stored in one Firebase project; the server (Cloud Functions) derives the plans, the Surrender % and the history.

## 2. The platform (shared by both apps and the server)

FOLK Surat runs on **one Firebase project, `folk-sadhana-app`** (region `asia-south1` for functions). Three code bases use it:

| Repo | What it is | Android package |
|---|---|---|
| `Sadhana-App-for-Admin` | the **Guide (mentor) app**, plus the same code built for the web at https://folk-guides.web.app | `org.folksurat.guides` |
| `Sadhana-App-for-Users` | the **Student app** | `org.folksurat.students` |
| `functions` | **Cloud Functions** (Node 22), `firestore.rules`, rules tests, tools, deploy scripts, docs | – |

The apps never talk to each other. They talk to **Firestore** (reads and a few direct writes, limited by the security rules) and to **callable Cloud Functions** (everything that needs a secret, a model, or a decision the client must not make). The server then writes the derived records (plans, Surrender %, history, scores) that the apps display. No app holds an AI key.

```
Student app ──┐                         ┌── Cloud Functions (triggers, schedules, callables)
              ├── Firestore (rules) ────┤        │
Guide app  ───┘   Auth (Google / email) └── OpenAI · Qdrant · Dropbox · Zegocloud · FCM
```

### 2.1 People and roles

* **HOD** (head of department). Several are allowed (role checks only; the account SBSD can never be removed or demoted). Sees every student and every guide's plan, adds/removes any admin, sets the AI budget, reviews targets.
* **Guide** – owns a team: his own students plus those of his Male Enablers (`teamGuide`). Boys only.
* **Male Enabler** – works under a Guide (`teamGuide`), owns some boys.
* **Female Enabler** – owns girls. She is the only admin (besides a HOD) who sees girls. She has no FOLK-residents target (boys only).
* **Students** – boys and girls of three kinds, by `users.role`: **Stay at FOLK** (residents of the ashram), **Stay at Hostel**, and **Stay at Localite** (living at home; any other value). Hostel and Localite compete together, apart from FOLK (`categoryOfRole`).
* **Gender separation** is enforced by the rules and the app queries: a boy is seen by his guide / team guide, the HODs and (when unassigned) any Guide / Male Enabler; a girl only by her Female Enabler (or any Female Enabler while unassigned) and the HODs. A missing gender counts as male in the apps and the rules.
* **Who may add whom** (`hierarchyCore.rolesThatCanBeAddedBy`, re-checked by the server): HOD → any role; Guide → Guides and Male Enablers; Male Enabler → Male Enablers; Female Enabler → Female Enablers. Nobody removes himself or the last HOD. `removeAdmin` supports `dryRun` (how many students become Unassigned). **Unassigned** = `guideId == ""`.
* One Google account can be both an admin and a student (a Female Enabler who is also a student): the rules tie every student rule to the caller's own uid, name, gender and category.

### 2.2 Sign-in and how an admin is recognised

* **Students** sign in with **email + password or Google** (Firebase Auth). Email/password exists so Google Play's reviewers can get in (see the Play Review account, §9). After the first sign-in the student completes the profile (name, gender, mobile, date of birth, residence role, commitment); `name` and `gender` can be set **once** (the rules refuse a change afterwards) because the name is the key of the sadhana reports.
* **Admins** sign in with **Google only**. The app calls `getAdminProfile`; the server matches the signed-in email to `adminUsers/{id}` (the id is the guide id, e.g. `SBSD`). A Google account that is not an admin is signed out with an explanation.
* **For the security rules** an admin is a signed-in, email-verified user whose lowercase email has a document in `guideEmails/{email}` (role, guideId). That collection is a server-written **mirror of `adminUsers`** (`syncGuideEmailMirror`): rules can only `get()` a known path, never query, so the email is the document id. Roles are the strings `HOD`, `GUIDE`, `MALE_ENABLER`, `FEMALE_ENABLER`.
* **Google Sign-In on Android** needs the app's signing **SHA-1 / SHA-256 fingerprints registered** under Project settings → Your apps, and the downloaded `android/app/google-services.json` kept in the app folder (it is committed; it holds no secret). Register: the **Play App Signing** key (Play Console → App integrity), the **upload key** (below) and each developer's **debug key** (`keytool -list -v -keystore ~/.android/debug.keystore`). After adding a fingerprint, download the new `google-services.json` into BOTH apps.
  * Guide upload key (`folk-guides-key.jks`, alias `folk-guides`): SHA-1 `34:C0:9B:E6:FC:2F:67:20:2B:10:C8:46:31:22:54:4D:1C:49:7B:65`, SHA-256 `02:58:ED:AD:73:78:F2:72:DB:BB:C4:48:32:89:03:CF:C3:C7:AB:7F:08:0B:38:5C:2B:2A:00:29:E8:6A:DE:B2`.
  * Student upload key (`folk-students-key.jks`, alias `folk-students`): SHA-1 `6A:FC:D8:55:89:50:42:B9:6E:4E:C4:7D:5C:B6:02:DA:76:78:E4:B9`, SHA-256 `75:E7:BB:EC:D3:18:45:AC:07:F5:99:39:BC:91:1B:56:AB:16:B5:B6:F6:8B:24:D6:50:D0:AE:ED:C6:B8:57:A3`.
  * The Play App Signing release key SHA-1 recorded for the Guide app is `C1:F0:D9:49:E2:0E:78:46:F8:E9:D7:B2:4D:C4:3C:E6:18:CE:95:50` (confirm in Play Console).
  * Fingerprints are public identifiers, not secrets.

### 2.3 Firestore: the collections

Every write path is closed unless a rule opens it (`firestore.rules`, one file, ~800 lines, default deny). "Server" below means a Cloud Function using the Admin SDK (bypasses rules). "Scope" means the admin may read it only for students he may see (`adminSeesScope`, from the `scopeGuide` / `scopeTeam` / `scopeGender` stamps).

| Collection | What it stores | Who writes / reads |
|---|---|---|
| `users/{uid}` | the student profile: name (write-once), gender (write-once), role (residence), guideId, teamGuide, commitmentRounds, readingCommitmentMinutes, dob, mobile, notification prefs, `isManualEntry` for students a guide added before they registered. Sub-collections (questions, dailyReading …) | student: own non-protected fields; admin: students in scope except owner/team/gender/scope fields (those only via `assignStudent` / the server); read by the student and scoped admins |
| `adminUsers/{id}`, `guideEmails/{email}`, `adminTokens`, `config`, `appConfig/versions` | the admin records, their rules mirror, FCM tokens, server config, and the **forced-update** minimum builds (`students.minBuildNumber`, `guides.minBuildNumber`) | `adminUsers` via callables only; `guideEmails`, `adminTokens`, `config` server-only; `appConfig` readable by everyone, written by the owner in the console |
| `sadhana-reports/{name}/dates/{date}` and `hostel-sadhana/{name}/dates/{date}` | the daily report FORMS (the only source of sadhana numbers). Document id is the student's **name**; the hostel form is separate | student writes own; scoped admin reads; the server stamps scope, scores, best stats, challenges |
| `booksRead/{uid}_{level}_{bookKey}` | a student's book: `isCurrentBook`, `startDate`, `commitmentDate` (due date), `endDate`, `commitmentSetBy` (`guide` / `student`), `commitmentSetById`, `finishedViaButton` | the student, and admins in scope (`assignBook` / `markBookFinished` in the Guide app) |
| `bookDoubts`, `bookmarks`, `bookHighlights`, `readingDays`, `rduaProgress` | reader data: doubts (to guide or AI), bookmarks, highlights/notes, per-day reading log, RDUA study progress | student writes own; scoped admins read doubts (and answer) |
| `interactionLogs/{id}` | an interaction the guide recorded: raw note, willingness, `topicAnswers`, `approvedSummary` (the server's analysis), `preAnalysis` | admins in scope; server fills the analysis; students never read |
| `associations/{id}` and `associationGuideNotes/{id}` | meeting requests/confirmations/completions between a student and a guide; the **guide's private notes** on a meeting live in the second collection (a student can never read them) | student requests; scoped admin confirms/completes; notes: scoped admins only |
| `litAssessments`, `holisticSuggestions`, `priorityReasons`, `priorityDismissals` | the LIT assessment (three independent 1–5 axes, never combined), legacy suggestions, "why this student needs attention" keys | admins; priority is server-written |
| `flaggedChatMessages` | student AI-chat messages the server judged worrying (distress / discouraged) | server writes; scoped admins read/review; never shown to the student |
| `studentChats/{uid}/messages|sessions`, `studentComments/{uid}/messages` | the student's AI chat (streamed reply documents) and the comment thread between a student's guides | student own chat; comments by admins in scope |
| `guidePlans/{adminId}` | the guide's **plan**: Today (cards, batch), This week (interactions by day, target tasks, other tasks), missing reports. One document per admin | server only; read by that admin and any HOD |
| `planChanges/{adminId}/items`, `seenMarkers/{id}`, `planOverrides`, `planMeta`, `studentPlanNotes`, `planRestored`, `topicPostponements` | "new" list for the plan badge, what an admin has seen (dots), removals/restores, the guide's constraints per student (`not_folk`, `stop_chanting_push`, `prefers_call` …), LATER postponements (`{uid}__{key}`) | server (and callables); `seenMarkers` written by the admin's own app |
| `studentSurrender/{uid}`, `studentSurrenderChecks/{uid}`, `surrenderDirty` | the **Surrender %** with its parts, series, 10% crossing `events`, `weekly` snapshots, open crossings; the student's one open surrender check (kind, points); marks for the minute recompute | server only; scoped admins read; never a student |
| `studentHistory/{uid}` | the student's history lines by category (Interactions & meetings, Surrender & targets, Sadhana, Books, Trips, Worries, Doubts); 30 newest | server only (`appendHistory`); scoped admins read |
| `interactionNeeds/{uid}` | what a student needs (the "Interactions needed" list) and the AI brief | server; scoped admins read |
| `guideTargets/{guideId}/targets/{id}` (+ `phases/{n}`) | compound targets (chanting / books / folk): goal, end date, phases, tasks with the named students, `excludedUids` | guide / HOD through the app and callables; plan trigger reads |
| `expeditions`, `expeditionRegistrations`, `expeditionExperiences` | trips, registrations, and "what the trip meant to me" | HOD / guides create trips; students register and write their experience |
| `chantingChallenges`, `chantingChallengeContributions`, `competition`, `competition-results`, `scoreMarkers` | guide-made chanting challenges (over a span of days) and their contributions; the weekly/monthly competition entries and results (top 3, byGender / byCategory) | server finalizes; students read what the rules open |
| `serviceAssignments`, `studentServices`, `rduaTopics`, `podcastModules`, `books`, `questions`, `musicCurriculum`, `musicProgress` | Service Bank, RDUA course, audio modules, the book library (Dropbox links), questions, My Music | admins write content; students write own progress |
| `calendarEvents`, `calendarTextBlocks`, `calendarEventTypeDescriptions` | the Guide calendar: mandatory (HOD) and personal events, and the pasted-text blocks they came from | HOD / owner guide |
| `boards/{id}`, `friendRequests`, `friends`, `friendGroups`, `voiceRooms`, `messages` | the Kanban board state, RDUA friends and voice rooms | per rules |
| `agentActions`, `agentChats`, `aiUsage`, `aiUsageSummary`, `aiUsageDays`, `aiBudget` | the Guide assistant's audit log and chats; the **AI ledger** (one document per model call), summaries, the month's budget | server writes; HOD reads usage and budget |

(When this table and `firestore.rules` disagree, the rules win. Older rollback copies `firestore.rules.live-before-*` are kept next to it.)

### 2.4 Security-rules principles

1. **Default deny.** A collection with no rule is closed.
2. **Admin = `guideEmails` document**; the role and guide id come from it. HOD sees everything; others by `adminSeesUser` (student documents: `teamGuide` / `guideId` / `gender`) or `adminSeesScope` (history and name-keyed documents: the server-stamped `scope*` fields; the old `guideId` field on a document is **not** used for visibility).
3. **Server-only fields.** `guideId`, `teamGuide`, scope stamps, badges, `bestChantRounds`… can only be written by the server or `assignStudent`.
4. **A student reaches only his own data**: by uid, by name (reports), by gender and category (competition).
5. **Derived records are never written by an app** (plans, Surrender, history, needs, AI ledger).
6. **Guide-only material** (private meeting notes, Surrender, history, flagged messages, LIT) is never readable by a student.
7. Every rules change is **proved on the emulator first** (`rules-tests/`) and deployed with `deploy-rules.sh`, which re-checks that unauthenticated reads are still denied and **rolls back by itself**.

### 2.5 Cloud Functions

All are in `functions/` (Node 22, region `asia-south1`, timezone `Asia/Kolkata` for schedules). `index.js` exports them; each file's header comment explains its rules. The list below is generated from the code (147 exports).

| Function | Trigger | What it does |
|---|---|---|
| `acceptFriendRequest` | callable | Student accepts a friend request (RDUA friends). |
| `addAdmin` | callable | HOD / senior admin adds an admin (role rules in hierarchyCore.rolesThatCanBeAddedBy); mirrors to guideEmails. |
| `addAiTopup` | callable | HOD adds an AI budget top-up for the month. |
| `aiCreditView` | callable | HOD's view of the AI budget, spend and the ledger summary. |
| `analyseInteraction` | callable | Analyses one saved interaction note with OpenAI (themes, concerns, commitments, next action). |
| `applyNotificationDefaults` | Firestore written users/{uid} | Gives a new / changed user the default notification preferences. |
| `archiveFinishedTrips` | schedule 5 0 * * * (Asia/Kolkata) | Archives trips that have finished. |
| `assignStudent` | callable | Moves a student to a guide / unassigned (the only writer of guideId / teamGuide). |
| `bookCommitmentReminder` | schedule 0 12 * * * (Asia/Kolkata) | Reminds students whose book due date is near. |
| `calendarBlockImmediateNotification` | Firestore written calendarTextBlocks/{blockId} | Notifies when a mandatory calendar text block is posted. |
| `calendarDayBeforeReminder` | schedule 0 19 * * * (Asia/Kolkata) | Reminds the day before a calendar event. |
| `calendarWeekAheadNotification` | schedule 0 7 * * * (Asia/Kolkata) | A week-ahead digest of calendar events. |
| `checkAndAdvanceIfAheadOfSchedule` | callable | Advances a target's phase early when every student is ahead. |
| `checkChallengeOnHostelSadhana` | Firestore written hostel-sadhana/{studentName}/dates/{dateKey} | Updates chanting challenges from a hostel report. |
| `checkChallengeOnSadhanaReport` | Firestore written sadhana-reports/{studentName}/dates/{dateKey} | Updates chanting challenges from a normal report. |
| `checkMobileTaken` | callable | Registration: is this mobile number already used. |
| `checkNameAvailable` | callable | Registration: is this name free (names are write-once keys). |
| `clearAdminToken` | callable | Removes an admin's FCM token on logout. |
| `dailyBirthdayCheck` | schedule 0 7 * * * (Asia/Kolkata) | Birthday notifications. |
| `dailyOverdueAssociationCheck` | schedule 0 9 * * * (Asia/Kolkata) | Flags meeting requests that are overdue. |
| `dailyPriorityCheck` | schedule 0 21 * * * (Asia/Kolkata) | Nightly sweep: priority reasons and every student's Surrender % (the same code as the live recompute). |
| `dailyRekeyCheck` | schedule 0 4 * * * (Asia/Kolkata) | Re-keys manual students who registered (manualRekey). |
| `dailySadhanaReminder` | schedule 0 8 * * * (Asia/Kolkata) | Morning reminder to submit the sadhana report. |
| `deleteAiTopup` | callable | HOD removes an AI top-up. |
| `deleteCompoundTarget` | callable | Deletes a target with its phases and tasks. |
| `deleteExpedition` | callable | Deletes a trip. |
| `deleteStudent` | callable | Deletes a student and their data (studentDeletion.js). |
| `deleteStudentAuthAccount` | callable | Deletes the student's Firebase Auth account. |
| `evaluateCompoundPlanDryRun` | callable | Dry run of a target's plan (what would be generated). |
| `extractCalendarEvents` | callable | Turns pasted text into dated calendar events (OpenAI). |
| `finalizeMonthlyCompetition` | schedule 10 0 1 * * (Asia/Kolkata) | Closes the month's competition: top 3 and badges. |
| `finalizeWeeklyCompetition` | schedule 5 0 * * 0 (Asia/Kolkata) | Closes the week's competition. |
| `findManualMatch` | callable | Matches a registering student to a manual entry a guide made. |
| `geminiExtractInteraction` | callable | Compatibility callable for older Guide builds (OpenAI now); delete once build 12 is gone. |
| `geminiSuggestNextAction` | callable | Compatibility callable for older Guide builds; delete once build 12 is gone. |
| `generateCompoundPlan` | callable | Generates a target's phases and tasks (AI + real student data). |
| `generateDailyEncouragement` | callable | The student's daily encouragement message (personal, data-aware). |
| `generateStudentSuggestions` | callable | Kept for older app builds; suggestions now live in the plans. |
| `getAdminProfile` | callable | Who is this signed-in email: role, id, team (matches adminUsers). |
| `getGenderDirectory` | callable | Name directory by gender for registration checks. |
| `getMyGuide` | callable | A student's own guide name. |
| `getVoiceRoomToken` | callable | Zegocloud token for RDUA voice rooms (backend currently a stub). |
| `guideAgentTurn` | callable | One turn of the Guide assistant (tools, confirmations, AI budget). |
| `guidePlansRefresh` | schedule * * * * * (Asia/Kolkata) | EVERY MINUTE: rebuilds the plans of the guides whose data changed (and the morning / scheduled refresh). |
| `includeInTarget` | callable | Puts a student back into a target he was taken out of. |
| `listAdmins` | callable | Admins visible to the caller. |
| `mergeManualEntryOnRegistration` | Firestore written users/{uid} | Merges a manual entry's data into the student who registered. |
| `middayGuideDigest` | schedule 10 11 * * * (Asia/Kolkata) | Midday digest to guides. |
| `middaySadhanaReminder` | schedule 0 11 * * * (Asia/Kolkata) | Midday reminder for missing reports. |
| `monthlySadhanaRetention` | schedule 0 3 1 * * (Asia/Kolkata) | Monthly retention of old report data. |
| `notifyGuideOnAssociationWrite` | Firestore written associations/{assocId} | Notifies a guide of a meeting request / change. |
| `notifyGuideOnDoubt` | Firestore written bookDoubts/{doubtId} | Notifies a guide of a student's doubt. |
| `notifyGuideOnExpeditionRegistrationWrite` | Firestore written expeditionRegistrations/{regId} | Notifies a guide of a trip registration. |
| `notifyGuideOnHostelSadhana` | Firestore created hostel-sadhana/{studentName}/dates/{dateKey} | Notifies the guide of a hostel report. |
| `notifyGuideOnSadhanaReport` | Firestore created sadhana-reports/{studentName}/dates/{dateKey} | Notifies the guide of a report. |
| `notifyStudentsOfNewTrip` | Firestore created expeditions/{tripId} | Push to students for a new trip. |
| `onAdminHierarchyChange` | Firestore written adminUsers/{id} | Re-computes hierarchy after an admin changes (students of a removed admin become Unassigned). |
| `onBookFinishedCheckPhase` | Firestore written booksRead/{docId} | A finished book may complete a book-target phase. |
| `onCompoundProposalWritten` | Firestore written guideTargets/{guideId}/targets/{targetId} | Notifies a HOD of a proposed target plan. |
| `onFriendRequestWritten` | Firestore written friendRequests/{requestId} | Notifies of a friend request. |
| `onInteractionSaved` | Firestore created interactionLogs/{logId} | Runs the analysis of a new interaction and its follow-ups. |
| `onStudentTokenWritten` | Firestore written notification/{name} | Keeps the student's FCM token mirror. |
| `onStudentValueChanged` | Firestore written users/{uid} | A student's rounds / books changed: checks the targets' phases. |
| `onUserHierarchySync` | Firestore written users/{uid} | Keeps scope fields in line when a user's guide / team changes. |
| `planChangeOnPhase` | Firestore written guideTargets/{guide}/targets/{id}/phases/{phase} | Records 'new' items in the plan-change list when a phase changes. |
| `planChangeOnUser` | Firestore written users/{uid} | Records plan changes from a student's commitment / category change; marks the Surrender recompute. |
| `planCorrection` | callable | The guide corrects a plan item (remove / restore a student's interactions, report ignore ...). |
| `planDirtyAssociations` | Firestore written associations/{id} | Marks the owning guide's plan dirty when Associations change (the minute worker rebuilds it). |
| `planDirtyBooks` | Firestore written booksRead/{id} | Marks the owning guide's plan dirty when Books change (the minute worker rebuilds it). |
| `planDirtyCalendarEvents` | Firestore written calendarEvents/{id} | Marks the owning guide's plan dirty when CalendarEvents change (the minute worker rebuilds it). |
| `planDirtyCompetitions` | Firestore written chantingChallenges/{id} | Marks the owning guide's plan dirty when Competitions change (the minute worker rebuilds it). |
| `planDirtyDoubts` | Firestore written bookDoubts/{id} | Marks the owning guide's plan dirty when Doubts change (the minute worker rebuilds it). |
| `planDirtyFlagged` | Firestore written flaggedChatMessages/{id} | Marks the owning guide's plan dirty when Flagged change (the minute worker rebuilds it). |
| `planDirtyHostelReports` | Firestore written hostel-sadhana/{name}/dates/{id} | Marks the owning guide's plan dirty when HostelReports change (the minute worker rebuilds it). |
| `planDirtyInteractions` | Firestore written interactionLogs/{id} | Marks the owning guide's plan dirty when Interactions change (the minute worker rebuilds it). |
| `planDirtyLater` | Firestore written topicPostponements/{id} | Marks the owning guide's plan dirty when Later change (the minute worker rebuilds it). |
| `planDirtyPriority` | Firestore written priorityReasons/{id} | Marks the owning guide's plan dirty when Priority change (the minute worker rebuilds it). |
| `planDirtyReports` | Firestore written sadhana-reports/{name}/dates/{id} | Marks the owning guide's plan dirty when Reports change (the minute worker rebuilds it). |
| `planDirtyServices` | Firestore written serviceAssignments/{id} | Marks the owning guide's plan dirty when Services change (the minute worker rebuilds it). |
| `planDirtySurrender` | Firestore written studentSurrender/{id} | Marks the owning guide's plan dirty when Surrender change (the minute worker rebuilds it). |
| `planDirtyTargets` | Firestore written guideTargets/{guide}/targets/{id} | Marks the owning guide's plan dirty when Targets change (the minute worker rebuilds it). |
| `planDirtyTrips` | Firestore written expeditions/{id} | Marks the owning guide's plan dirty when Trips change (the minute worker rebuilds it). |
| `postponeTopic` | callable | LATER: postpones a topic of Today to a date. |
| `pruneChatHistory` | schedule 20 0 * * * (Asia/Kolkata) | Prunes old chat messages. |
| `pruneChatOnNewDay` | Firestore created studentChats/{uid}/sessions/{day} | Prunes the chat when a new day's session starts. |
| `pruneReadingDaysOnCreate` | Firestore created readingDays/{id} | Trims old reading days. |
| `refreshPlan` | callable | The guide's manual Refresh of the plan. |
| `regenerateCompoundPlan` | callable | Re-plans a target's remaining phases (after an extension, an exclusion ...). |
| `registerAdminToken` | callable | Stores an admin's FCM token. |
| `removeAdmin` | callable | Removes an admin (dryRun tells how many students become Unassigned). |
| `rescoreOnCommitmentChange` | Firestore updated users/{uid} | Recomputes points when the commitment changes. |
| `rescoreOnHostelReport` | Firestore written hostel-sadhana/{studentName}/dates/{dateKey} | Recomputes the day's points from a hostel report. |
| `rescoreOnSadhanaReport` | Firestore written sadhana-reports/{studentName}/dates/{dateKey} | Recomputes the day's points from a report. |
| `resumeAiForMonth` | callable | HOD resumes AI after the budget guard paused it. |
| `retryDraftTargets` | schedule */15 * * * * (Asia/Kolkata) | Every 15 minutes: retries targets whose plan could not be generated (draft). |
| `saveNotificationPrefs` | callable | Saves a user's notification preferences. |
| `savePlanSettings` | callable | Saves the guide's daily number (1–12, default 4). |
| `scrubAssociationGuideNotes` | Firestore written associations/{id} | Removes legacy guideNotes from the association document the student reads (they live in associationGuideNotes, guide-only). |
| `searchStudents` | callable | Student search for friends (never returns a mobile number). |
| `sendExperienceRequests` | schedule 0 8 * * * (Asia/Kolkata) | Asks students who joined a trip to share their experience. |
| `sendRoomInvites` | callable | Voice-room invites. |
| `sendStudentNotification` | callable | A guide sends a push to a student (book assigned, meeting ...). |
| `setAiBudget` | callable | HOD sets the monthly AI budget. |
| `setTeamGuide` | callable | Sets an enabler's team guide. |
| `stampScopeAssociationGuideNotes` | Firestore created associationGuideNotes/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new AssociationGuideNotes document so admins are limited by scope. |
| `stampScopeAssociations` | Firestore created associations/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new Associations document so admins are limited by scope. |
| `stampScopeBookDoubts` | Firestore created bookDoubts/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new BookDoubts document so admins are limited by scope. |
| `stampScopeBookmarks` | Firestore created bookmarks/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new Bookmarks document so admins are limited by scope. |
| `stampScopeBooksRead` | Firestore created booksRead/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new BooksRead document so admins are limited by scope. |
| `stampScopeChallengeContributions` | Firestore created chantingChallengeContributions/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new ChallengeContributions document so admins are limited by scope. |
| `stampScopeCompetition` | Firestore written competition/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new Competition document so admins are limited by scope. |
| `stampScopeExpeditionExperiences` | Firestore created expeditionExperiences/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new ExpeditionExperiences document so admins are limited by scope. |
| `stampScopeExpeditionRegistrations` | Firestore created expeditionRegistrations/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new ExpeditionRegistrations document so admins are limited by scope. |
| `stampScopeFlaggedChatMessages` | Firestore created flaggedChatMessages/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new FlaggedChatMessages document so admins are limited by scope. |
| `stampScopeHolisticSuggestions` | Firestore created holisticSuggestions/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new HolisticSuggestions document so admins are limited by scope. |
| `stampScopeHostelSadhana` | Firestore created hostel-sadhana/{studentName}/dates/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new HostelSadhana document so admins are limited by scope. |
| `stampScopeInteractionLogs` | Firestore created interactionLogs/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new InteractionLogs document so admins are limited by scope. |
| `stampScopeLitAssessments` | Firestore created litAssessments/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new LitAssessments document so admins are limited by scope. |
| `stampScopeRduaProgress` | Firestore created rduaProgress/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new RduaProgress document so admins are limited by scope. |
| `stampScopeSadhanaReports` | Firestore created sadhana-reports/{studentName}/dates/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new SadhanaReports document so admins are limited by scope. |
| `stampScopeServiceAssignments` | Firestore created serviceAssignments/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new ServiceAssignments document so admins are limited by scope. |
| `stampScopeStudentChats` | Firestore created studentChats/{docId} | Stamps scopeGuide / scopeTeam / scopeGender on a new StudentChats document so admins are limited by scope. |
| `studentChat` | callable | The student assistant (library + trusted sites + personal data); flags distress for the guide. |
| `studentGuideNote` | callable | The guide's note about a student via the plan (constraints such as not_folk, stop pushes). |
| `studentHistoryOnAssociation` | Firestore written associations/{id} | Writes the meaningful event of Association into the student's history. |
| `studentHistoryOnAssociationNote` | Firestore written associationGuideNotes/{id} | Writes the meaningful event of AssociationNote into the student's history. |
| `studentHistoryOnBook` | Firestore written booksRead/{id} | Writes the meaningful event of Book into the student's history. |
| `studentHistoryOnConcern` | Firestore written flaggedChatMessages/{id} | Writes the meaningful event of Concern into the student's history. |
| `studentHistoryOnDoubt` | Firestore written bookDoubts/{id} | Writes the meaningful event of Doubt into the student's history. |
| `studentHistoryOnInteraction` | Firestore written interactionLogs/{id} | Writes the meaningful event of Interaction into the student's history. |
| `studentHistoryOnTripExperience` | Firestore written expeditionExperiences/{id} | Writes the meaningful event of TripExperience into the student's history. |
| `studentHistoryOnUser` | Firestore written users/{uid} | Writes the meaningful event of User into the student's history. |
| `suggestCompoundPlan` | callable | Suggests a plan for a new target. |
| `surrenderCheckOnChange` | Firestore written studentSurrender/{uid} | A Surrender crossing: creates / reconciles the student's surrender check, prepares its AI points once, announces it. |
| `surrenderCheckOnLit` | Firestore written litAssessments/{id} | A saved LIT assessment recomputes the Surrender % at once. |
| `surrenderOnInteraction` | Firestore created interactionLogs/{id} | A saved interaction closes crossings and recomputes the Surrender % from what was said. |
| `surrenderRecompute` | schedule * * * * * (Asia/Kolkata) | EVERY MINUTE: recomputes the Surrender % of students marked dirty (reports, meetings, interactions, commitments). |
| `sweepExpiredChallenges` | schedule 0 2 * * * (Asia/Kolkata) | Closes expired chanting challenges. |
| `sweepInteractionAI` | schedule every 20 minutes (Asia/Kolkata) | Every 20 minutes: analyses interactions the trigger missed. |
| `syncGuideEmailMirror` | Firestore written adminUsers/{name} | Mirrors adminUsers to guideEmails/{email} (what the security rules read). |
| `unpostponeTopic` | callable | LATER: brings a postponed topic back now. |
| `upcomingTripReminder` | schedule 30 9 * * * (Asia/Kolkata) | Reminds students of an upcoming trip. |
| `updateAdmin` | callable | Edits an admin (role / name / email). |
| `updateBestStatsOnHostelSadhana` | Firestore written hostel-sadhana/{studentName}/dates/{dateKey} | Best day / best chanting stats from a hostel report. |
| `updateBestStatsOnSadhanaReport` | Firestore written sadhana-reports/{studentName}/dates/{dateKey} | Best day / best chanting stats from a report. |
| `voiceToEnglishText` | callable | Speech to English text for the interaction logger. |
| `weeklyGoalEvaluation` | schedule 0 4 * * 1 (Asia/Kolkata) | Monday: evaluates every target's phase. |

### 2.6 Hosting

The **Guide app also runs as a website** at https://folk-guides.web.app (Firebase Hosting site `folk-guides`, built from the same Flutter code with `flutter build web`). It is for guides and HODs only. A computer window gets a side navigation and compact tiles (tile width capped, `MediaQuery` only – no `LayoutBuilder` anywhere in the Guide app). `index.html`, `.js` and `.json` are served no-cache so a deploy is what everybody gets next load. **Standing rule: after any Guide code change, rebuild and redeploy the website** with `./deploy-web.sh` (it builds, deploys, restores the generated plugin files and `pubspec.lock`, and proves the live `main.dart.js` has the size of the build).

## 3. Data rules and invariants (do not break these)

1. **Sadhana numbers come only from the daily report FORMS** (`sadhana-reports` and `hostel-sadhana`). The japa counter and the reading timer never write a report; the ABCDE chanting number is the form's. Missing data is *missing*, never zero-filled into other numbers.
2. **Category separation.** A student's reports count in his *current* category's form (hostel form vs the normal form); the calendar merges both so history survives a residence change; scores, Surrender and competitions use the current category. Hostel and Localite compete together, apart from FOLK.
3. **A student's name is write-once and trimmed** (it is the key of reports, competition and notification documents). So is gender.
4. **No student data is ever overwritten.** A manual entry made by a guide is *merged* when the student registers (`mergeManualEntryOnRegistration`); a conflict is kept (`pendingManualMergeConflict`), never overwritten.
5. **Derived records are server-only**: `guidePlans`, `studentSurrender*`, `studentHistory`, `interactionNeeds`, `aiUsage*`, scope stamps, scores. An app never writes them.
6. **Guide-only stays guide-only**: Surrender %, history, LIT, flagged messages and a guide's private meeting notes are never readable by a student (and the student app never shows the distress flag; students are told once how the assistant works).
7. **One code path for the Surrender %** (`surrenderState.recordSurrender`): the nightly sweep, the live recompute and the backfill all call it. Changing the formula means changing `surrender.js` `CONFIG` and then running the backfill (silent, backed up) – never two formulas.
8. **A finished book is never current** (`assignBook` is a transaction that refuses a completed book). One topic per book on a student's card.
9. **History lines are meaningful events only**, with stable ids (a trigger delivered twice, or a sweep run twice, writes nothing twice), the newest 30, never a plan rebuild or a status re-check (`studentHistory.appendHistory` guards this; `cross_…` lines are refused as step lines, a Surrender 10% crossing is `surrender_ev_…`).
10. **A student is never refused an AI answer because the guides' monthly AI budget is used up** (the guard applies to guide-side AI only).
11. **UI rules** (enforced by tests): colour literals live in the theme (`restyle_test`), no `LayoutBuilder`, no spinners (ghost placeholders instead), 48 dp touch targets, text scale 1.0/1.3/1.6 must not overflow, dark and light, phone and website.
12. **Never change `appConfig/versions` minBuildNumber yourself** – the owner sets it after a release is live (it force-updates old builds).
13. **Every server change must keep working with the builds already in the field** (additive fields, compatibility callables such as `geminiExtractInteraction`, new list items that an older app can still draw). Remove a compatibility path only after the new build is adopted (listed in `functions/HANDOVER.md`).

## 4. Credentials and secrets (values are never in git)

| What | Where it lives | Used by |
|---|---|---|
| OpenAI API key | `functions/credentials/openai-key.json` → `{"apiKey": "…"}` | `chat.js`, `guideAgent.js`, `interactionAI.js`, `calendarEvents.js`, `goals.js`, `surrenderCheck.js`, `doubtAi.js` |
| Qdrant (the Srila Prabhupada library search) | `functions/credentials/qdrant-key.json` | `chat.js` |
| Dropbox | `functions/credentials/dropbox-key.json` | book links / library fetch |
| Zegocloud (voice rooms) | `functions/credentials/zegocloud-key.json` (the backend is currently a stub) | `rduaFriends.js` |
| Gemini (legacy, no longer used for AI) | `functions/credentials/gemini-key.json` | – |
| Firebase Admin service account | `Sadhana-App-for-Admin/credentials/service-account.json` | **tools and scripts only** (`node tools/…`): backfills, audits, probes. Not used by an app |
| Android upload keystores + passwords | `<app>/android/folk-guides-key.jks`, `folk-students-key.jks`, `android/key.properties` (`storePassword`, `keyPassword`, `keyAlias`, `storeFile`) | release builds. **Keep an off-PC backup of both `.jks` files and the passwords: Play will not accept an update signed with another upload key** |
| `google-services.json` | `<app>/android/app/` (committed: contains no secret) | Firebase config of each app |
| Guide `.env` | `Sadhana-App-for-Admin/.env` (from `.env.template`) | legacy; nothing in the app reads a secret any more |

* **All of the above are git-ignored** (`credentials/`, `*.jks`, `*.keystore`, `key.properties`, `.env`, `*service-account*.json`, `*-key.json`). The functions deploy **packages `functions/credentials/` with the code** (it is not in the `firebase.json` ignore list), which is how the functions read the key files at run time.
* **Rotate or replace a key**: put the new JSON in `functions/credentials/<file>.json` (same shape; the `.template` files show it), then **redeploy the functions** that use it (`./deploy-functions.sh <names>`, or all of them for the OpenAI key; a warm instance keeps the old key until it is replaced). Revoke the old key at the provider. For the service account: create a new key in Google Cloud → IAM → Service accounts, replace `credentials/service-account.json`, delete the old key. For an upload keystore: only Play Console's "request upload key reset" can change it.
* **AI budget guard and costs** (`aiUsage.js`, `aiBudgetFns.js`): every OpenAI call made on behalf of a guide is recorded (`aiUsage`, one document each; daily and monthly summaries) and **guarded**: the default monthly budget is **₹1,000** (`DEFAULT_SETTINGS.monthlyInr`, USD→INR 88) per `aiBudget` document; when it is used up a guide's AI call gets a synthetic 429 (`ai_budget_used_up`) and the apps say so in words. A HOD sees spend, per-type cost and per-guide use (`aiCreditView`), sets the budget (`setAiBudget`), adds a top-up (`addAiTopup`) or resumes (`resumeAiForMonth`). The student app's AI (chat, daily encouragement) is recorded under "Student app" and never blocked. Models are chosen in code: `chat.js` (`gpt-5.4-nano` classify, `gpt-5.4` answers), `guideAgent.js` `agentConfig` (a strong planner, a smaller model for simple steps), `interactionAI.js` and `surrenderCheck.js` (`gpt-5.4-mini`). `tools/aiCostEstimate.js` and `tools/ai-samples.js` estimate and sample costs.

## 5. Development setup on a new PC

Install: **Git**, **Flutter 3.44+** (the project has been built with 3.44.9 and 3.47.7), **JDK 17** for Gradle/Android builds, the **Android SDK** (compileSdk 36, an NDK as Flutter asks), **Node 22** for the functions (any recent Node runs the tests), the **Firebase CLI**. The Firestore **emulator needs Java 21+ with firebase-tools 14/15**; with only JDK 17 use `npx firebase-tools@13.35.1` (that is how rules tests were run on the current PC).

```bash
git clone <Guide repo>      && cd Sadhana-App-for-Admin && flutter pub get
git clone <Student repo>    && cd Sadhana-App-for-Users && flutter pub get
git clone <functions repo>  && cd functions && npm ci
```

Then add the git-ignored files (ask the owner; see §4): `android/key.properties` + keystore in each app, `functions/credentials/*.json`, `Sadhana-App-for-Admin/credentials/service-account.json`, and `firebase login` (or `firebase login:ci` / a service account for scripts).

* **Keep everything off C:** on a PC with a small system drive set `TMP`/`TEMP`, `GRADLE_USER_HOME`, `PUB_CACHE`, `ANDROID_HOME`/`ANDROID_SDK_ROOT` and `JAVA_HOME` to another drive (this project's helper is a small `env.sh` that exports them). Do not run `flutter clean` unless a build really fails.
* **Android debugging:** USB debugging (developer options) or wireless debugging (Android 11+: pair with `adb pair <ip>:<port>`, then `adb connect <ip>:<port>`); `flutter run -d <device>`. The debug key's SHA must be registered for Google Sign-In (§2.2).
* **Gradle/Android settings that matter:** `compileSdkVersion 36`, release `minifyEnabled true` + `shrinkResources true`, the release signing config reads `android/key.properties` and **fails the build loudly if it is missing** (it never falls back to debug signing).
* **Tests**
  * Guide / Student app: `flutter test` (≈2,600 and ≈2,090 tests; widget tests use `fake_cloud_firestore`, `pumpScreen`, `prepareApp`, `phone()` helpers in `test/support/`), `flutter analyze` (**0 errors**; a few hundred old infos/warnings are the known baseline).
  * Functions: `node --test test/*.test.js` (≈2,040 tests, `test/fakeDb.js` is an in-memory Firestore).
  * Rules: `functions/rules-tests/*.rules.test.js` and `functions/rules-tests-student/*.test.js` on the emulator: `firebase emulators:exec --only firestore --project folk-sadhana-app "node --test <file>"` (run from `functions/`; the emulator refuses a `firebase.json` whose rules file is outside the project directory; one file at a time because they share the emulator).
* **Scripts** live in `functions/`: `deploy-functions.sh`, `deploy-rules.sh`, `check-invokers.js`, and `functions/tools/` (backfills, audits, probes, `renderCapabilities.js`); the Guide repo has `deploy-web.sh`.

## 6. Deploying

* **Functions – `./deploy-functions.sh name1 name2 …`** (from `functions/`). Deploy **only the functions whose behaviour changed** (every function ships the whole code folder; list the exported functions that call the changed modules). It runs `firebase deploy --only functions:…` and then `check-invokers.js`, which proves every callable just deployed is reachable from inside the container: a callable is opened to the public (Cloud Run "allUsers") only when it is first **created**; if that one IAM call fails the apps get a bare 403 forever and no later deploy repairs it (this is what happened to `deleteCompoundTarget` on 22 Oct 2026).
  * Quota: Firestore/Cloud Functions mutation quotas make large deploys fail with 429 ("DEPLOY FAILED"). Wait ~2 minutes and retry, in batches of 5–8 functions. If discovery times out set `FUNCTIONS_DISCOVERY_TIMEOUT=180` and do not run a web build at the same time.
  * An "Authentication Error: credentials no longer valid" line followed by "Deploying…" is a warning; the deploy continues with the project's access.
* **Rules – `./deploy-rules.sh`**: runs every `rules-tests/*.rules.test.js` on the emulator against the exact file, deploys `firestore:rules`, checks that unauthenticated reads of `users`, `priorityReasons`, `adminUsers` are still 403, and **redeploys the rollback copy** (`ROLLBACK=` at the top of the script, a `firestore.rules.live-before-*` file) if anything fails. Update the rollback copy before each rules change (copy what is live).
* **Website – `Sadhana-App-for-Admin/deploy-web.sh`** (Hosting target `folk-guides`).
* After a deploy, check the logs of the changed functions in the console for a minute.

## 7. Release process (Play Store)

1. **Version**: `pubspec.yaml` `version: x.y.z+N` – the name before `+` is `versionName`, the number after is Android `versionCode` (must be higher than every build ever uploaded). Guide and Student have their own numbering. A guard test (`hierarchy_test.dart` in the Guide app) pins the version.
2. Run the full suites (§5), analyze with 0 errors.
3. **Build** (from the app folder, with the env exported): `flutter build appbundle --release --obfuscate --split-debug-info=<symbols dir>`. Use a **different symbols directory per build** (this project keeps `D:\folk-updates\symbols\<app>-<versionCode>`) and keep them forever: they de-obfuscate crash stack traces. `pub get` may rewrite `pubspec.lock` and desktop plugin registrants on another Flutter version – `git checkout` them, commit only `pubspec.yaml` and the version-guard test.
4. **Prove the build**: unzip the `.aab` (it is a zip) and check that strings of the new code are inside `base/lib/arm64-v8a/libapp.so`, that no `*.jks`, `key.properties` or credentials are inside, and note the size. Copy the AAB to `D:\folk-updates\release-aabs\` (names like `student-1.1.6+12.aab`).
5. **Tag** the commit (`v1.1.6+12`) and push the tag.
6. **Upload** in Play Console: **Student → Production** (create release, upload the AAB, release notes ≤ 500 characters per language); **Guide → Internal testing** (the guide app is not public). Wait until the new build is live/installed.
7. **Only then** the owner sets `appConfig/versions` → `students.minBuildNumber` / `guides.minBuildNumber` to the new build number, which makes older builds show the blocking "update" screen. Do it after adoption, never before.

## 8. Adding or changing a feature safely

1. Read the header comment of the file you touch and `functions/HANDOVER.md` (a dated log of every rule and why).
2. **Decide where the logic lives**: anything that needs a secret, a model, other students' data or must not be forgeable goes in a Cloud Function / trigger and is stored in a server-only collection; the app only displays it.
3. **Additive and backwards-compatible**: new fields, never renamed or removed while an older build may still read them; a new list item must degrade gracefully in the previous app (e.g. send a title the old app can draw and the detail in a new field).
4. **Write the test first or with the change**: a functions test with `FakeDb` for the logic; a widget test for the screen (phone 360 dp and website 1280, light/dark, scales 1.0/1.3/1.6); a rules test when a rule changes. Put the cause of a bug in the test's name.
5. **Rules**: edit `functions/firestore.rules`, add/extend a `rules-tests/*.rules.test.js`, save the live copy as the new rollback, deploy with `deploy-rules.sh`.
6. **Deploy order**: rules → functions (changed ones only) → website → app release. A server change must work with the builds in the field (§3.13).
7. Update `functions/HANDOVER.md`, this guide when a rule changes, and (assistant) `agentTools.js` / `agentCapabilities.js` + `node tools/renderCapabilities.js` (`AGENT_CAPABILITIES.md` is generated and tested) and `agentCatalog.js` (what the assistant tells guides about the app; its `verify` entries are checked against the Guide code).

## 9. Operations notes and troubleshooting

* **Play Review account**: a real student account for Google's reviewers: email `folkstudents@gmail.com` (password in the owner's records), name "Play Review", male, Stay at FOLK, guide FOLK, 16 rounds, disclosure acknowledged. Keep it enabled; do not delete or rename it. It appears as a normal student in the FOLK HOD's plan.
* **"Assigned book not in the calendar"**: a HOD's calendar "My items" view hides items of other guides; books for a HOD carry no guide so they always show; the line "N items of other guides hidden on this day" appears when something is hidden (tap All guides).
* **Google Sign-In developer error (code 10)**: a fingerprint is not registered, or `google-services.json` was not replaced after registering it (§2.2).
* **A callable answers 403**: the Cloud Run service is not public (`check-invokers.js` finds it; fix in Cloud Run → Security, or recreate the function).
* **"DEPLOY FAILED" 429**: quota, wait and retry smaller batches. **Discovery timeout**: `FUNCTIONS_DISCOVERY_TIMEOUT=180`.
* **A stale Surrender check / title**: titles are built from the current % (`surrenderCheck.titleOf`); a check that no longer matches because of a formula change is closed by `reconcile`.
* **Plan not updating**: the plan is rebuilt every minute for guides whose data changed (`guidePlansRefresh`, `planDirty*` triggers); the guide's Refresh calls `refreshPlan`; check `guidePlans/{id}.updatedAt` and the function logs.
* **FakeDb and arrays**: `FieldValue.arrayUnion` is a sentinel in the test fake – use read-modify-write in code that must be tested.
* **fake_cloud_firestore** expands dotted keys into nested maps (real Firestore does not): read both shapes (`dottedField()` in the Guide app).
* **Flaky timing test**: `book_reader_core_test` ("loadBook TIMING") measures parsing time; run it alone if the machine is busy.
* **Disk full on C:**: builds and tests still run if every cache is on another drive (§5); never delete user data to make room.
* **Old PC → new PC**: `pubspec.lock` and desktop registrants change with the Flutter version; revert them before committing.
* Secrets must never be pasted into chats, commits, issues or docs.

## 10. The Guide app: screens, features and the rules behind them

### 10.1 Shell and navigation

Three tabs behind a floating pill navigation (kept alive in an `IndexedStack`, so scroll and state survive switching tabs and themes); on a computer a side navigation replaces the pill and an assistant **side panel** (440 dp) can open beside the page.

* **Home** – the dashboard: the **This week** card (navy: Targets / To contact / Done) and **Today's tasks** (dark green: Targets / To contact / Done) that open the Plan page; then ONE row of three equal widgets: **FOLK Boys Board · Calendar · Targets**. A "new" badge shows what changed in the plan since the guide last left the Plan page.
* **Analysis** ("Folk analysis") – ABCDE, Week planning, Priority students (Interactions needed), Guide targets, Leaderboard (and, for a HOD, the Assistant log and the AI cost panel).
* **Tasks** – Add student, Submissions, Add admin, Notifications.
* The **Assistant** is a floating button on every page (a panel on the website); see §10.9.
* Light / Dark / Auto theme (Appearance button). A forced-update screen blocks a build older than `appConfig/versions.guides.minBuildNumber`.

### 10.2 The student board and profile

* **FOLK Boys Board** (`Home/FolkBoysWorkspace.dart`): Kanban columns – one per guide and an "Unassigned" column; each card is a student built live from Firestore (scoped by `StudentScope`). Long-press drag to reassign: a HOD can move anyone; others can claim unassigned students (of their gender) or release their own. `assignStudent` is the only writer of `guideId` / `teamGuide`.
* **Student profile**: the **Surrender %** bar (tap: the breakdown of every part, the weekly line "52 → 61 → 70 → 80 → 70" and the latest 10% crossings with their causes), commitments card, sadhana calendar (reports from both forms), scores and graphs, **Books** panel (assign a book with a finish-by date, mark finished, unassign), doubts, comments thread between the student's guides, **history** (by category: Interactions & meetings, Surrender & targets, Sadhana, Books, Trips & services, Worries, Doubts – outcome lines only), LIT assessment, music, trip experiences.

### 10.3 The plan: Today and This week (`PlanPage`, built by `functions/guidePlans.js`)

The server builds **one plan per admin** (`guidePlans/{adminId}`) and keeps it current: a data change marks it dirty (`planDirty*` triggers) and `guidePlansRefresh` rebuilds it **every minute**; the guide's Refresh calls `refreshPlan`. A HOD's plan is **his own** students, targets and meetings; the other guides appear as one summary line each under "Guide by guide". Probe/test accounts never appear.

**Today** shows three blocks – *Follow-ups*, *Target tasks*, *Other tasks* – with a one-line summary "Total tasks today: N · Done D · Left L". The rules:

* **ONE card per student with ALL his topics** (a worry, a doubt, poor sadhana, chanting step, a book, a FOLK invitation, a surrender check, a meeting…), so the guide talks to him once. The card sits in the block of its most important topic: **a worry → Follow-ups; else any target topic (chanting, reading, FOLK, a surrender check that carries the FOLK invitation) → Target tasks; else a follow-up (doubt, sadhana slip) → Follow-ups; else Other tasks.**
* **Topics** (`TOPIC_LABELS`): worry (`concern`), doubt, poor sadhana (`sadhana_slip`: five days of not meeting a commitment), the daily-report and timings habits (discussed once), good sadhana (five days of full commitments → the next step), chanting / reading / FOLK target steps, festival boost, **surrender check**, a book due or overdue, a meeting request or confirmed meeting, "Target ended", a topic that came back from Later, "Doubts waiting".
* **Ticks come only from saved records** – a topic is done when the guide's interaction report-back (recorded through the assistant or the logger) covers it, or the data finished it (book finished, commitment reached, doubt answered…). Nothing is ticked by a tap. A done topic stays, dimmed, for the day.
* **Carry-over:** nothing missed disappears; an unfinished card is there again tomorrow (marked carried over) until done or its reason ends.
* **The daily number** (default **4**, 1–12, changed only by asking the assistant: `plan_batch_size_set`; the page shows the muted-gold note "Up to N students a day for your targets") limits **only students who come just for the guide's targets**, counted across **all targets together**. Everything else is always in Today at once: worries, doubts, surrender checks, books due/overdue, streaks, meetings, Later returns, target ended, festival boosts; if such a student also has target topics they ride along on his card without using a place. Order: a worry first, then by Surrender % (highest first); who the targets pick when the number allows only some: chanting/reading → closest to the next ladder step, FOLK → highest % first. Festival boost raises the number by half.
* **LATER** (`topicPostponements/{uid}__{key}`, `topicLater.js`): a second button on every postponable topic: tomorrow / next week / next month / mid next month / a chosen date, a note, and either **only this topic or the whole card**. Until the date the plan hides it (not done, not ticked); This week and the calendar show it on its date; on the date it returns with the note and "Was 70% when postponed, now 76%". If it is finished earlier it is shown "Done early" (ticked, never returns open). A date after a target's end removes the student from that target (`excludedUids`) and his promise comes back as a follow-up. A postponed surrender check is not prepared or announced while it waits. No history line is written for a postponement.
* **Target ended**: when a target's end date is reached Today shows "Target ended — choose" with *Delete target* and *Extend end date* (extending re-plans the remaining phases). Nothing is planned for an ended target until then.
* **Books**: one topic per book ("📖 Gita — due Fri 30 Oct" / "— overdue by N days", every day while overdue, with "Counts for your book target (1 of 4)" when it applies; "Assign a book" / "Assign next book" when the book target needs one). **A book that is not finished is never shown as finished:** a book topic is ticked by the data (finished, or given a new date) or by an interaction the guide held with him today; a tick the data gave goes again when the data changes back (a finish taken back, a new date put back: `carryDone`). A student on a book target whose book is not due yet is **on track** (no card; This week says "on track — due 30 Nov").
* **Meetings**: one topic per meeting – a student's request ("Meeting request", button Open meeting), a confirmed one ("Meeting — Fri 30 Oct, 5 PM", replaces the request), held (ticked), cancelled (gone everywhere, no history line). The guide's notes on a meeting are private (`associationGuideNotes`).

**This week**: the totals ("Interactions this week: N · Done · Left"), *Interactions* day by day (names only, done ones ticked), *Target tasks* – **one combined line** "Chanting 3 of 5 · Reading 2 of 4 · FOLK 1 of 3" with each pending student's combined next step ("Amit — 12 → 16 · invite to FOLK (direct)") – and *Other tasks* (meetings, trips, competitions, book deadlines of the week, Later returns). A third tab, **Missing reports**, lists who has not reported.

### 10.4 Interactions

* **Three ways to add an interaction, one save** (`saveInteraction` → one real `interactionLogs` record for that student, then ONE `interaction_logged` notification): (1) the assistant's **Do it** mode records it from the guide's words; (2) **Guide me** answers 'add an interaction with Ravi' with ONE button, *Record interaction — Ravi*, which opens the form already for him (with nobody named the form opens with a student picker; never an Open profile beside it); (3) **Associations → Add interaction** picks a student (search, own scope) and opens the same form. The form (`RecordInteractionDialog`): student, what happened (type or mic), his willingness (optional: more / same / less), the topics to tick when he has open ones on Today; plain code, no AI to save. Every record gets a line in the student's card history (Interactions & meetings) by the server at once (a manual student's too), reads his willingness into the Surrender %, and ticks the matching Today topics.
* A guide **records an interaction** by typing or speaking (voice → `voiceToEnglishText`) and saving. The server analyses it in the background (`onInteractionSaved` / `sweepInteractionAI`, OpenAI): themes, concerns, commitments, revelations, ABCDE and LIT evidence, circumstances, a next action; the assistant can also send a ready analysis with the report (`preAnalysis`). A report-back can state per topic what the student answered (`topicAnswers`), which closes **only those topics**; an unscoped report closes them all. A *willingness* choice (very willing … unwilling) feeds the Surrender attitude part.
* **Interactions needed** (Analysis → Priority students, `interactionNeeds/{uid}`) is the same function the plan uses, so the two never disagree: reasons per student from the targets, sadhana slips, five-day streaks, doubts, worries and surrender.
* **Worries** come from `flaggedChatMessages`: the student's AI chat is screened and a message that sounds discouraged or distressed is flagged for the guide (never shown to the student). A worry stays above everything in order, whatever the %.

### 10.5 The Surrender % (`functions/surrender.js`, `surrenderState.js`, `surrenderCheck.js`)

A number 0–100 for each student, **for guides and HODs only**. Parts (100 in total):

| Part | Points | How |
|---|---|---|
| Commitment | 10 | what he committed to (rounds, reading minutes) |
| Sadhana actually done | 40 | **R × (15 C + 15 Rd + 10 T) / 40…** precisely: `R` = days with a report in the last 30 / 30; `C` = average rounds on reported days / 16 (cap 1) × 15; `Rd` = average reading minutes / 60 (cap 1) × 15; `T` = average timing score (wake-up, temple, sleep, japa finish) × 10. From the report FORMS of his current category only |
| Association – attitude & willingness | 20 | his interactions and meetings with the guide in the **last 30 days**: the guide's willingness choices (latest three count 50 / 30 / 20 %); met but no willingness noted = neutral (0.5, and the plan asks the guide to note it); none in 30 days = 0; "ignore daily reports" = 0 |
| LIT | 20 | his latest LIT assessment |
| Bonus | 10 | four pieces of 2.5: 50+ rounds on any day; 180+ minutes of reading on any day; his chanting average above his commitment; his reading average above his commitment (last 30 days, equal does not count) |

A part with no data scores 0 and the others are never scaled up. **Caps**: a student not living in FOLK is held at 90%; a record with a part missing is held at 95. Stages by 10% (Start, Consistency, Deepen, Commit, Strict sadhana, Surrender) each have a focus and questions (`interactionNeeds.LEVELS`).

* **Never a day behind:** the nightly sweep (`dailyPriorityCheck`) and the live recompute use the same code. A saved LIT recomputes at once; reports, interactions, meetings and commitment/category changes mark `surrenderDirty` and the `surrenderRecompute` worker (every minute) recomputes each marked student once. The guide's "ignore daily reports" choice recomputes quietly.
* **History:** every 10% crossing is an **event** in `studentSurrender.events` (day, from → to, up/down, cause: reports, lit, interaction, meeting, commitment, category, ignore, formula, earlier) and the % of each week is kept in `weekly`. A genuine crossing is also one history line "Surrender 70 → 80 ↑ (new daily reports)". A change of the **formula** (a recompute) is recorded as a *formula* event and opens **no** check and no history line. `tools/backfillSurrenderHistory.js` rebuilt the events from existing data (dry run / `--apply` / `--verify`, backed up).
* **The surrender check** (`studentSurrenderChecks/{uid}`, ONE per student at a time, a topic on his card): created when he crosses a 10% mark by his own doing. Kinds from his history: **growth** (first rise to a level, or back to one he had), **drop** (fell back to a level already passed: a concern check, "Surrender check — dropped to 70% ↓": what changed, how to help him recover, no repeated growth advice), **pattern** (two or more genuine drops in 21 days: "dropped twice in 3 weeks", steadiness), **formula** (none). The AI points are prepared **once per crossing** (one cheap call; a fallback if the AI fails) from his reports, interactions, meetings, services, trips, LIT and calendar. Titles and lines are built live from the **current %**; a check that no longer matches because the formula moved him is closed quietly (`reconcile`). Gaps (no LIT, no interaction in 30 days, no reports, willingness not noted) appear as points with the right button and tick themselves when filled.
* The assistant explains any student's percent from the server (`get_surrender_breakdown`: every part, what raises it, what holds it back, the 1–3 most effective next steps).

### 10.6 Targets – one journey per student

A guide / HOD can have one **chanting**, one **reading** (books) and, except a Female Enabler, one **FOLK-residents** target (`guideTargets/{guideId}/targets/{id}`, phases of about a week with tasks naming the students; `generateCompoundPlan`, `regenerateCompoundPlan`, `weeklyGoalEvaluation` on Mondays, `checkAndAdvanceIfAheadOfSchedule`, HOD review screen). They work together centred on the Surrender %:

* **Ladder:** chanting 2 → 4 → 8 → 12 → 16 rounds; reading up to 60 min/day.
* **FOLK readiness = Surrender %:** a boy not living in FOLK is eligible for the FOLK target and any FOLK invitation **only at 40% or more**: 40–59 a gentle invitation, 60+ a direct one; below 40 only sadhana and steadiness. Never a FOLK resident, a girl, a boy the guide marked `not_folk`, or in his exam dates (exams and festivals from the calendar: no new demands in exams; boost and invitations in festivals).
* **Selection:** chanting/reading targets pick the students closest to their next step; the FOLK target picks eligible boys, highest % first.
* **One combined picture** on This week and on the **Targets page** (Home widget): three cards about half a screen tall – **Chanting (gold), Reading (sky blue), FOLK (purple; not for a Female Enabler)** – each with the goal and end date (or "Not set" + *Set target*), progress ("3 of 5 boys at 16 rounds"), the phase, the next students, and the state (Active / Ended — choose / Achieved 🎉); tap → the target (delete / extend) or the create flow. One column on a phone, two on the website.
* **The surrender check carries the FOLK point** (so it is not repeated as a separate topic) when it is a growth check.
* The assistant explains a student's next step and any target's progress (`get_student_journey`).

### 10.7 Calendar

`GuideCalendarPage` shows, live, everything the guide has to do: the plan's tasks (Today exactly as in Today; This week on its days), meetings in every state, **every book due date** ("📖 Ravi — Gita due"), follow-ups, trips, competitions, **each target's start, the end of every phase, and its end date ("Target ended — choose")**, the students' target days, postponed topics on their return dates (✓ Done early), and the guide's own events. Tapping a day lists its items grouped like Today (Follow-ups, Target tasks, Other tasks, Meetings, Events) and each row opens the right screen. A **HOD sees his own items by default** ("My items") and everyone's under **All guides**; the page says how many items of other guides it is hiding on the selected day (books always show for a HOD). Mandatory events (a HOD posts them: exams, festivals, programs) shape the plan: no new demands in exam dates, a boost and invitations around festivals. `extractCalendarEvents` turns pasted text into dated events. Reminders: day-before, week-ahead.

### 10.8 Other modules

* **Books**: a library of books (Dropbox links, managed with the Book link manager); a guide assigns a book with a finish-by date (`BookActions.assignBook`: a transaction writing `booksRead` with `commitmentDate`, `commitmentSetBy: guide`, `commitmentSetById`, and a "book assigned" push); a student may set his own date; `markBookFinished`; `unassignBook`. A due date appears in the calendar, This week (the week it falls in) and Today (on the date and every day while overdue). Book reminders go to students.
* **Doubts**: students ask the guide or the AI; the guide sees "Doubts waiting" and answers (the assistant can draft an answer from the library first, then trusted sites, for the guide to confirm).
* **Meetings** (`associations`): request → confirm → completed/cancelled; overdue ones are flagged daily; the guide's private notes.
* **Music**: `musicCurriculum` and each student's `musicProgress` (My Music).
* **Trips** (`expeditions`): create a trip, registrations, post-trip experiences ("what the trip meant to me"; students are asked after the trip), reminders.
* **Chanting competitions & challenges**: a guide creates a collective chanting challenge over a span of days (`chantingChallenges`, contributions); weekly and monthly competitions are finalised by schedule (top 3, badges, `competition-results` by gender and category; hostel+localite together, FOLK apart); the Leaderboard ranks total points.
* **Points** (`scoring.js`, `scoreRecompute.js`): every report is scored on the server (rounds, reading against the commitment, timings, services…); students see "points" and a breakdown; best-day / best-chanting stats are server-written.
* **Service Bank**: 19-step service curriculum and per-student assigned services. **LIT**: private, three independent 1–5 axes, never combined. **Priority students**: a checklist of reasons, no blended score. **Submissions**: who reported today. **Add student / Add admin**: manual students (merged later on registration), admin management by role rules. **ABCDE**: one card per area of practice.
* **Notifications** (`routing.js`, `pushSend.js`, `notificationDefaults.js`): FCM pushes by type, per-type preferences, quiet hours for plan notifications, one push per message; "unseen" **dots** come from `seenMarkers/{admin}` (an admin's own app writes it; until the server confirms a write the dot logic treats it as seen, so nothing flickers).

### 10.9 The AI assistant (Guide side)

`guideAgentTurn` runs one turn of a tool-using assistant (a strong model plans, a smaller one does simple steps). It can find students, read plans, targets, calendar, reports, books and the Surrender breakdown / journey (read tools answered by the server or the phone), and **write** through tools (assign a book, answer a meeting, add a calendar note, record an interaction with its analysis, set the daily number, postpone a topic, include/exclude a student in a target, set a target's end date, assign/unassign students…). Writes show what will happen and wait for the guide's confirmation (some need a second confirmation); each is logged in `agentActions` and undoable where possible. `AGENT_CAPABILITIES.md` (generated from `agentCapabilities.js` + `agentTools.js`) lists every capability; `agentCatalog.js` is what it tells guides about the app. Guide-side AI is under the **AI budget guard** (§4). The assistant never explains a percent, a student's next step or a target's progress from memory: it calls `get_surrender_breakdown` / `get_student_journey`.

### 10.10 Source map

`lib/Home` board and Home dashboard · `lib/Pages` screens (`PlanPage`, `TargetsPage`, `GuideCalendarPage`, `GoalHomePage`, `CompoundGoal*`, managers) · `lib/utils` data layer (`PlanData` plan model, `PlanToday` placement, `PlanCalendar` / `AutoCalendar` calendar feed, `PlanTopicActions` Later and target-end actions, `StudentScope`, `SurrenderData`, `SeenMarkers`, `UnseenAggregates`) · `lib/actions` write helpers shared by screens and the assistant · `lib/agent` the assistant on the phone · `lib/widgets` the shared design system (`Guide*` components) · `lib/theme` tokens and colours (`GuideColors`). Server counterparts: `guidePlans.js`, `dailyBatch.js`, `interactionNeeds.js`, `topicLater.js`, `surrender*.js`, `goals.js`, `studentHistory.js`, `guideAgent.js`.
