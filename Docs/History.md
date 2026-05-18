# Project History

This is the long-form story of how this project happened — and why it ended up being more personal (and more emotional) than “I wanted to build a tool”.

It started as a very human problem: life was asking for care, but work kept eating every available hour. And when you’re tired, stressed, or simply drowning in daily admin, the things that matter most are often the first things you postpone.

## 1. When “I’ll do it later” becomes a pattern

One of the recurring pain points was medical logistics.

If you’ve never had to find a new doctor through health insurance, it can sound like laziness. But if you have… you know it’s a battle. You go to the insurer website, you copy phone numbers, you start calling — and then you hit reality:

- numbers that don’t work anymore,
- doctors who moved, stopped answering, or never offered what the page promised,
- “we don’t do that here”,
- “the next slot is in two months”,
- and the endless follow-ups, spread across calls and WhatsApp messages.

It’s not rare to lose four, five, six hours in a single day doing that. And the worst part is: sometimes you don’t “give up” because you don’t care — you give up because you’re already exhausted, and you just can’t.

## 2. The human assistant phase (and the relief of being helped)

At one point, when I was making good money, I hired a friend to help me for about an hour (maybe an hour and a half) per day.

I remember thinking, very explicitly: “this is not abuse.” Which sounds dramatic, but it’s true — my brain was wired to feel guilty for asking for help. I paid what I could. I knew he deserved more. But the agreement was honest and limited: a small daily slot, focused on the stuff that was silently ruining my life.

The work was simple, but it mattered:

- organizing emails,
- organizing calendar,
- reminding me of appointments,
- and, most importantly, calling me before important events.

That last one is hard to explain until you live it. He would call me one hour before an appointment and say, with the firmness I didn’t have with myself: “stop what you’re doing. Go now. Fix this.” That saved things.

But even that had obvious limits. He had his own life. He couldn’t be my external brain forever — and he couldn’t realistically have access to the place where most of my chaos lived: WhatsApp.

Then the hard part happened: I ran out of money. I lost the human assistant. And suddenly I was alone again with every pending thread.

## 3. Software help: Codex felt like magic… and then it felt expensive

Around that time I was using Codex a lot. I was unemployed, trying to study, learn, build things — and the idea of an “assistant” stopped feeling like sci‑fi and started feeling… plausible.

I connected Codex to Gmail and Calendar and tried to use it as a small, practical helper:

- read emails,
- summarize,
- categorize,
- suggest actions.

It worked. It genuinely worked. And that almost made it worse — because it wasn’t sustainable. Small tasks could burn through a big chunk of usage, sometimes a third of the “5-hour” window, sometimes half. I kept thinking: “this is incredible… but I can’t afford it as a lifestyle.”

And then the obvious thought showed up:

“Okay… but what if it could do WhatsApp too?”

## 4. WhatsApp is not “just chat” — it’s where life happens

WhatsApp isn’t only messages. For me it’s health insurance, doctors, family, work, the place where problems appear first.

My first attempt was as direct as possible: let the model drive WhatsApp Desktop on macOS via Accessibility tooling.

It worked — but it was heavy. Really heavy. The model had to understand UI. Understand windows. Understand where to click. Spend tokens interpreting a layout that changes. It wasn’t “working”, it was “looking at a screen and guessing”.

At some point I had a very clear thought:

I don’t want the model to watch my screen. I want it to work.

So I started building an MCP tool surface that turned “WhatsApp” into a small, stable set of actions: list chats, read recent messages, send messages, wait for events. That was the real beginning of this repo.

And I still remember the feeling: in two or three days of iteration with Codex, the thing got good fast. Almost too fast.

And then it got too expensive fast too.

## 5. The sentence that changed everything: “it could be free”

My partner said something that was so obvious that my brain almost ruined it with my (very annoying) habit of correcting people.

He said: “wow… this could be free, right?”

And my first impulse was to “correct” him — but that whole argument happened inside my head. I didn’t actually correct him. I just *almost* did, because I can be extremely literal in the worst possible moments.

Because the truth is: the intelligence itself *is* free in the sense that it’s public. It exists. You can run models. You don’t *have* to pay a company for “AI” as a concept.

What isn’t free is *compute*. The expensive part is paying for processing — whether that’s cloud tokens or hardware and electricity.

And the funny part is: this is someone I love, someone who knows me well enough to handle my literal brain without asking me to change it. He understands my nuance even when I’m being annoyingly precise.

There was this tiny pause — the kind where you can almost hear your own thoughts — and then my brain just exploded into an “oh.”

Out loud, what came out of me was basically: “wait… maybe it *can* be free.”

Because that’s what his sentence unlocked: if compute is the bottleneck, then maybe I can move the compute to my own machine.

It was a real Eureka moment. We were on the phone, he had to go back to work, and the conversation just… ended. But my head didn’t. I stayed there, grateful, suddenly motivated, suddenly seeing the whole project become viable in a way it hadn’t been five minutes earlier.

And that reminded me of LM Studio.

I hadn’t used it seriously in almost a year. But I thought: “wait… what if I run this locally?”

## 6. LM Studio, and the shock: local models got good

I have a powerful Mac (M3 Max), and I still had the old memory: local reasoning was slow, painful, kind of impractical.

But I opened LM Studio again and it was a shock.

Models got better. Tool-calling got better. It wasn’t just “tokens per second” — it was the amount of real work happening inside those tokens.

I connected LM Studio to the MCP tools and let it try the WhatsApp workflow.

It understood. It used the tools. It didn’t fight the interface. It went straight to the point.

And that’s the moment the project stopped being “a WhatsApp controller” and became “a local assistant runtime”.

## 7. Memory… and then: sensitive data

If it’s going to be a real assistant, it needs memory.

But it also needs *the right kind* of memory — and boundaries.

I didn’t want CPFs, insurance numbers, cards, and personal details living inside a generic memory blob. If something leaks into a message, if it goes to the wrong place, that’s not “oops”, that’s dangerous.

So the concept of Sensitive Data became necessary: separated, auditable, and treated differently. I wanted the assistant to be useful. I didn’t want it to be irresponsible.

## 8. Why Apple/macOS/Swift (and why it’s not aesthetic)

This project is “macOS-first” for a reason.

Apple Silicon made local compute feel normal — unified memory means that even a simpler Mac with 16GB can run a local model. It may be slower, it may need a smaller model, but it can run. On Windows, “16GB RAM and integrated graphics” usually means “no local LLM for you” unless you have a discrete GPU with enough VRAM.

And there’s another reason that matters even more for a personal assistant: voice.

macOS gives you strong public APIs for Text-to-Speech and Speech Recognition. And for Portuguese specifically, there was an unexpected twist: the system voice can sound more natural sometimes, but Swift’s public voices (like “Fernanda Enhanced”) can be *more reliable* with accents, cedillas, and punctuation — while the Siri voice isn’t even available through the public Swift API.

For an assistant, reliability matters more than “pretty”.

## 9. When WhatsApp Desktop became friction: WebView

Eventually, the native WhatsApp Desktop integration started to get in the way.

So I brought WhatsApp Web *inside* the app, via a WebView.

That gave me:

- more control,
- fewer external dependencies,
- less interference from the user,
- and a more consistent integration surface.

At that point, the macOS app was no longer “just a server.” It became an environment: UI, persistence, tools, logs, and the place where the assistant lives.

## 10. The moment I realized it isn’t just for me

After it started working, I showed it to my family. To my partner. To my mom.

And I had this very practical thought: “I could host more than one assistant on my machine.”

Most of the time, the model is idle. The constant cost is usually WhatsApp polling, state, logs, and operational bookkeeping. Different people receive messages at different times, so you can host multiple profiles without being saturated.

For example: I could host an assistant for my partner, my mom, maybe my stepfather. If they all receive messages at the same time, things get slower — but it still works. The model is already loaded.

But then the obvious operational problem appears: they’re not on my machine. They won’t open LM Studio. They won’t read logs. They won’t manage memory and subjects locally.

And that is how the mobile-client idea was born: not as “a nice extra”, but as a necessity if this ever wants to become a real product.

This story is not finished. It’s barely starting — and it will keep growing as the project (and my life) keeps moving.
