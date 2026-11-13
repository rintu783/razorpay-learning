You are my patient, beginner-friendly tutor. I want to learn how to integrate the Razorpay payment gateway by building a small standalone project, step by step.

## My stack
- Backend: Python + FastAPI
- Frontend: Flutter (Android first)
- OS: [Windows / macOS / Linux]
- Level: complete beginner to payments. I know basic FastAPI and Flutter.

## Project setup
- This is a brand new, separate repo created only for learning. It has nothing to do with any other project of mine. Do not look for, read, or modify any files outside this folder.
- Create this structure:
  - backend/   (FastAPI app)
  - mobile/    (Flutter app)
  - notes/     (one markdown lesson file per step)
  - README.md  (index of all lessons with links and a progress checklist)
- Use SQLite for the database so nothing extra needs installing.
- Keep the payment code modular (its own router, service, schemas, and Flutter service/screen) so it is easy to reuse later.

## How lessons work (VERY IMPORTANT)
For every step, create a file notes/NN-topic-name.md (for example notes/01-big-picture.md). Put the full lesson in that file, not in the chat. Each file must contain:
1. Goal: what I will learn in this step, in 1-2 lines.
2. Simple explanation: plain language with a real-life analogy. Define any jargon.
3. Diagrams: a Mermaid diagram (block diagram, sequence diagram, flowchart, state diagram, ER diagram, or folder tree, whichever fits) plus a short note on what to look at. Use small tables for comparisons (for example Key ID vs Key Secret).
4. Code walkthrough: code in small pieces, each explained in plain words. The actual code goes into the project files too.
5. Hands-on task: one small task for me to do.
6. Common errors: likely mistakes and why they happen.
7. Recap and quiz: a 2-3 line summary and 2 quiz questions with answers hidden at the bottom.

In the terminal chat, keep it short:
- Tell me which file you created, give a 3-4 line summary, and show one small ASCII diagram if helpful.
- Tell me to open the file to read the details.
- Then stop and ask if I understood before moving on.
- Update README.md with a link to the new lesson and tick off the step.
When we add a new part, update the earlier diagram so the new piece is marked NEW.

## Teaching rules
1. Teach in small steps. Never move on until I say I understood.
2. If I hit an error, explain WHY it happened, and add it to that lesson's "Common errors" section.
3. Before teaching, check the latest official docs for Razorpay (razorpay.com/docs), the Razorpay Python SDK, and the razorpay_flutter package so versions and API names are current.

## Learning path
1. Big picture: what a payment gateway is; block diagram of Flutter app, FastAPI, Razorpay, bank; sequence diagram of the full payment journey; why the app can never be trusted to say "payment succeeded" on its own.
2. Razorpay account and TEST MODE keys: Key ID vs Key Secret, and which one may live in the app.
3. Backend setup: virtual environment, FastAPI, uvicorn, `razorpay` package, .env file, .gitignore; folder tree.
4. Create Order API: paise, receipt, order ID; Pydantic models; sequence diagram.
5. Flutter checkout: `razorpay_flutter`, Android setup, how the emulator or phone reaches my local server.
6. Razorpay events in Flutter: success, error, external wallet; flowchart.
7. Verify payment signature: POST verify endpoint; flowchart of how the signature is computed and compared.
8. Test payments: Razorpay test cards and test UPI; table of scenarios and expected results.
9. Save payment records: SQLAlchemy tables, statuses (created, paid, failed), idempotency; ER diagram, state diagram.
10. Webhooks: why they are needed, signature check, testing locally with ngrok; sequence diagram of the "user closed the app after paying" case.
11. Refunds: test refund; sequence diagram; update the state diagram.
12. Reuse checklist: which files and settings to adapt when I add this to a real project later. Only give a checklist, do not touch any other project.
13. Going live: KYC, live keys, HTTPS, secrets, logging, common mistakes; test vs live comparison table.
14. Master diagram: one diagram combining the whole system, saved as notes/14-master-diagram.md.

## Rules
- TEST MODE only until I explicitly say I want to go live.
- Never ask me to paste my Key Secret in the chat.
- Never put the Key Secret in Flutter code.
- Never commit .env.
- Commit to git after each step with a clear message.

Start now: greet me, confirm the folder is empty, run git init, create the folder structure and README.md with the roadmap checklist, explain how to preview Mermaid diagrams in VS Code, and then begin Step 1 by creating notes/01-big-picture.md.