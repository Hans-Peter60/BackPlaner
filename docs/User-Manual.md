# BakePlanner – User Manual

Revised: 7 November 2026 · App version 2.3

> Translated from the German original, `Benutzerhandbuch.md`. Where the two
> differ, the German version is authoritative.

---

## Contents

1. [What BakePlanner does](#1-what-bakeplanner-does)
2. [System requirements](#2-system-requirements)
3. [Key concepts](#3-key-concepts)
4. [The tab bar](#4-the-tab-bar)
5. [Recipe database](#5-recipe-database)
6. [My recipes](#6-my-recipes)
7. [Baking instructions and reminders](#7-baking-instructions-and-reminders)
8. [Creating a new recipe](#8-creating-a-new-recipe)
9. [Editing a recipe](#9-editing-a-recipe)
10. [Scheduled steps (list and timeline)](#10-scheduled-steps-list-and-timeline)
11. [Reminders on the Lock Screen](#11-reminders-on-the-lock-screen)
12. [Baking history](#12-baking-history)
13. [Shopping list](#13-shopping-list)
14. [Settings](#14-settings)
15. [Units, amounts, and serving sizes](#15-units-amounts-and-serving-sizes)
16. [Privacy, moderation, and terms of use](#16-privacy-moderation-and-terms-of-use)
17. [Frequently asked questions and troubleshooting](#17-frequently-asked-questions-and-troubleshooting)
18. [Known limitations](#18-known-limitations)
19. [BakePlanner on Android](#19-bakeplanner-on-android)

---

## 1. What BakePlanner does

BakePlanner is a baking scheduler for bread, rolls, and pastry. What sets it apart from a plain recipe collection is that **it works out the timing for you**:

- A recipe isn't just a list of ingredients; it's a series of **processing steps with durations**.
- From those durations the app calculates the **start time of every single step**.
- You can plan backwards: "the bread should be ready at 6:00 p.m." — and the app tells you when to start the sourdough.
- Every step gets a **local reminder**, including the automatically inserted steps "turn on the oven" and "baking is finished".

On top of that: a shared public recipe database, your own recipes on the device, ingredient import from photos and web pages, shopping lists sorted by shelf, a baking history with photos and measurements, a starter diary for sourdoughs refreshed on a schedule with a ripening estimate, recipe variants with comparison and bake results, four baker's calculators (dough temperature, replace flour, starter TA, dough weight), the bake mode on the Apple Watch, widgets with “Done” and “Shift”, on-device translation of public recipes with a glossary of baker's terms, and Siri commands for the next step and starter feedings (see [chapter 11](#11-reminders-on-the-lock-screen)).

### Quick start: your first baking plan in five steps

1. Open **Recipe database** and pick a recipe — or create one of your own under **Create new recipe**.
2. In the recipe, tap **Plan**.
3. Choose **Start from** or **Done by** and set the date and time.
4. Check the calculated start times and tap **Set reminders**.
5. Open the **Timeline** tab to review every appointment as a timeline or a list.

Reminders require BakePlanner to be allowed to send notifications. The full explanations are in [chapter 7](#7-baking-instructions-and-reminders), [chapter 10](#10-scheduled-steps-list-and-timeline), and [chapter 17](#17-frequently-asked-questions-and-troubleshooting).

---

## 2. System requirements

| Item | Value |
|------|-------|
| Devices | iPhone (including iPhone Duo, folded and unfolded), iPad and Apple Watch (bake mode, see chapter 10). On a Mac with Apple silicon the iPad version runs from the Mac App Store ("Designed for iPad"). Android phones and tablets: see [chapter 19](#19-bakeplanner-on-android) |
| Operating system | iOS/iPadOS 26.0 or later; watchOS 26 for the watch app; macOS 26 for the Mac version; Android 9.0 or later |
| Orientation | iPhone: portrait and landscape · iPad: all orientations |
| Languages | German, English, French (switchable in Settings) |
| Appearance | Light and dark mode, Dynamic Type |
| Internet | Needed for the public recipe database and iCloud sync. Your own recipes, planning, and reminders work entirely offline; changes sync later. |
| iCloud | Your own recipes, scheduled steps, shopping lists, baking histories, starter diary and pantry sync through iCloud across all devices using the same Apple Account, provided iCloud is on; so do the settings, the saved collections and the custom units (through iCloud's key-value store, the latest change wins). The language, the consent to the cloud analysis, the list filters last chosen and the reminders themselves stay with each device. |
| Permissions | Notifications (for reminders), photo library and camera (for recipe images) |
| Sign-in | **Not** required for baking, for your own recipes, or for the public database. Signing in with Apple is voluntary: with it, the authorship of your published recipes applies on all your devices (see [chapter 14](#14-settings)). |

The app asks for notification permission on first launch. Without it, baking steps are still calculated and listed under "Scheduled steps", but **no reminders appear**.

---

## 3. Key concepts

These six terms turn up throughout the app:

**Recipe**
The top-level unit: name, description, image, rating, tags, an optional link to the source, total weight, and working time.

**Component**
A sub-preparation within a recipe — "sourdough", "preferment", "main dough", "scald", for instance. Each component has a number (its sort order) and its own ingredient list. This is the heart of the data model: BakePlanner is built for multi-stage doughs.

**Ingredient**
Always belongs to a component. Consists of a number, an amount, a unit, a name, and optionally a fraction (numerator/denominator, labelled **Z / N** in the app).

**Processing step**
A work instruction with a step number and a duration. The duration is stored in minutes; you can enter it in hours and minutes as well ("1:30", "1h 30", "1.5 h"), see [chapter 8](#8-creating-a-new-recipe). The step number is a decimal and carries a special meaning:

- **Whole numbers (1, 2, 3 …) are main steps.** They run one after another.
- **Decimals (2.1, 2.2, 2.3) are parallel steps within a main step.** They run at the same time, and only the *longest* duration in the group counts towards the total. Steps that make a component (sourdough, pre-dough, soaker …) start 5 minutes apart, in the order of their step numbers: nobody weighs out four pre-doughs in the same minute, and the reminders arrive staggered accordingly. All other parallel steps finish together with their group.

Example: if you start a sourdough (12 h) and a scald (2 h) at the same time, give them steps 1.1 and 1.2. The next main step, 2, begins after a little over 12 hours — not after 14.

**Serving size**
A scaling factor for every amount: 0.5 / 1.0 / 1.5 / 2.0. **1.0 is the recipe exactly as stored.** 2.0 doubles every amount and the displayed total weight. Instead of a factor you can enter a **dough weight** in grams or have it worked out from your tin with the scale symbol next to the field (see [chapter 15](#15-units-amounts-and-serving-sizes)). The choice applies to the whole open recipe: the recipe page, the baking instructions and the shopping list all use the same factor (see [chapter 15](#15-units-amounts-and-serving-sizes)).

**Storage**
Where a recipe lives. There are two options, and the **Publish** switch when saving decides who can see it:

| Storage | Who sees it? | Where does it live? | Editable? |
|---------|--------------|---------------------|-----------|
| **On this device only** (switch off) | only you | on the device, backed up through your iCloud | yes, any time |
| **Public for everyone** (switch on) | every user of the app | in the recipe database | yes, by you as its author |

A recipe you're **not allowed to publish** — out of a book, say — stays on the device. Through iCloud it's still on all your devices, and **More (⋯) → Export recipes** (see [chapter 14](#14-settings)) exports it as a file.

---

## 4. The tab bar

After launch the app opens on the **Recipes** tab. Along the bottom runs the tab bar with the four areas you need every day; each tab remembers where you were when you switch to another:

![BakePlanner's recipe list with the tab bar along the bottom](images/en/hauptmenue.png)

*The "Recipes" tab is the starting point: every recipe, the "More" menu with the calculators and the settings, the "+" for a new recipe.*

| Tab | Purpose |
|-----|---------|
| **Recipes** | Every recipe in one list: your own on the device, the ones you published and the public ones of all users — with the filter chips **Local / Published by me / Public** (see [chapter 5](#5-recipe-database)) |
| **Shopping lists** | All the shopping lists you've created |
| **Baking history** | Past bakes with comments and photos — as a list, gallery, top list, photo cloud or statistics |
| **Timeline** | Every scheduled baking step as a timeline or a list |

At the top right of the **Recipes** tab sit three buttons:

| Button | Purpose |
|--------|---------|
| **Filter** | The minimum rating, variants and the facets (duration, day flow, leavening, flour, dough yield, equipment, baking history) for the list |
| **More (⋯)** | The four baker's calculators **Dough temperature** (the water temperature for a desired dough temperature), **Replace flour** (swap the flour type, adjust the water), **Starter TA** (use a starter of a different dough yield, adjust the water) and **Dough weight** (the dough a loaf tin or a proofing basket takes), the backup — **Import recipes** (read a backup file or a single exported recipe) and **Export recipes** (your own recipes as a file, all or a selection), see [chapter 14](#14-settings) — and the **Settings** (language, defaults, baking plan, account) |
| **+** | **Create new recipe** — from scratch or imported from photos, a web page, or copied text |

**The "Up next" bar.** As soon as a baking plan is running, a bar floats above the tab bar of the Recipes tab with the step that is coming up: the step text, the recipe name, the time, and a countdown in minutes ("in 42 min"). The recipe rows scroll underneath it, so the bar stays in view. When a step's time has come, it switches to **"Due now"** with the elapsed time ("5 min ago") for an hour — until you mark the step as done in the notification or the next step falls due. Tapping the bar switches to the "Timeline" tab. With no step ahead it stays hidden.

The back arrow at the top left returns you from any opened screen to its list. Whatever lies as a sheet over a recipe — the baking instructions, the shopping list, editing — is closed with **Close** at the top left or a swipe down.

### On the iPad

On the iPad the tab bar sits at the top in the title bar and the search field below it across the full width; the rating filter, **More** and **+** stand on the right as on the iPhone (only on an iPad up to 11 inches held upright does the rating filter move into the **More** menu, because the three buttons do not fit beside the tab bar there). The app can be opened in **several windows** side by side (from the app switcher or with ⌥⌘N), say the recipe on the left and the timeline on the right.

With a keyboard these shortcuts apply (holding ⌘ shows them):

| Shortcut | Effect |
|---|---|
| ⌘1, ⌘2, ⌘3, ⌘4 | Recipes, Shopping lists, Baking history, Timeline tab |
| ⌘N | Create new recipe |
| ⇧⌘F | Search recipe |
| ⌘, | Settings |
| ⌥⌘N | New window |

---

## 5. Recipe database

Since version 2.0 the recipe database is **one list for every recipe**: the public ones you or other users have shared, and your own recipes on the device (see [chapter 6](#6-my-recipes)). Sorted alphabetically, with three filter chips below the search field — **Local**, **Published by me**, **Public** — that can be switched on and off individually and keep their state.

A symbol before each name shows the source: an iPhone for recipes on the device, a person symbol for the ones you published, and a globe for the public recipes of other users. Switch **Public** off and, next to your local recipes, what remains is the list of what you published yourself.

![List of public recipes with search and filter](images/en/oeffentliche-rezepte.png)

*In the recipe database you can search for and open public recipes.*

### Searching and filtering

- **Search field** at the top: searches recipe names.
- **Switch the search scope**: below the search field you can choose between **Name** and **Tags**. With "Tags", the search runs over keywords ("rye", "wholemeal", "sourdough", for example).
- **Filter chips** below the search field: **Local** (recipes on the device), **Published by me** (your own recipes in the database) and **Public** (the recipes of other users). Each chip switches its source on or off on its own; a public recipe always belongs to exactly one of the two cloud chips.
- **Collections** in the second chip row: **For tomorrow morning**, **Quick bread**, **Pure sourdough**, **Not baked for a while** and **Favourites** – each sets a ready-made combination of the facets (see below). A second tap clears it again.
- **Filter symbol** at the top right: minimum rating (All ratings, 1–5 stars and up), variants and the facets. While a filter is active, the symbol is shown filled. In a narrow iPad window (Split View, unfolded iPhone Duo) the filter sits in the **More (⋯)** menu as the submenu **Filter recipes**.
- **Pull down** to refresh the list from the cloud.

"No recipes loaded" means there was no internet connection at launch — pull the list down once. "No matching recipes" means a filter is active.

### Opening a public recipe

A recipe opens as **one continuous page**: image, name and description at the top, then serving size and dough weight, the weight, **Share recipe** and the dough-yield line, below them three buttons, then the total ingredients, the components and the processing steps with their durations — the same layout as your own recipes (see [chapter 6](#6-my-recipes)), only without rating, baking history and export.

- **Plan** — opens the baking instructions with the schedule as a sheet over the recipe (see [chapter 7](#7-baking-instructions-and-reminders)). The schedule is only worked out once you open the sheet.
- **Shopping list** — put the ingredients on a shopping list (see [chapter 13](#13-shopping-list))
- **Save as my own recipe** — keep a copy on your device (see below)

### Translating a recipe

By default, BakePlanner automatically translates public recipes into your app language — **entirely on the device** (Apple Translation) — covering the recipe name, description, tags, component and ingredient names, and step texts. You can turn this off under *Settings → Translation → Automatically translate public recipes* (see [chapter 14](#14-settings)).

- **On (default):** the recipe database already translates the names, descriptions and tags of recipes written in another language in the background, and when you open a recipe the app automatically translates the rest — components, ingredients and steps — if no translation exists yet. If one does, it appears at once. With the app set to German, a German recipe naturally stays as it is. Because the language is already settled this way, the globe symbol doesn't appear in this mode.
- **Off:** a recipe always shows first in the language it was written in. The **globe symbol** appears at the top right instead, letting you choose between Deutsch, English, and Français yourself. A checkmark in the menu shows which language is currently displayed; choose it again to go straight back to the original.

Notes:

- **Units** aren't touched by the recipe translation. The app shows them in its own language anyway (see [chapter 15](#15-units-amounts-and-serving-sizes)).
- The first translation into a language takes a moment (a brief delay for an automatic translation, or a progress indicator replacing the globe for a manual one). After that it's cached and available instantly.
- The first time, iOS may ask whether it may download the language packs for the translation. If you decline, recipes stay in their original language; with automatic translation off, it can be caught up later through the globe symbol.
- **Baker's terms are translated by a glossary.** Words such as Brühstück, Quellstück, Kochstück, Anstellgut, Stockgare or Stückgare — in compounds like Weizenanstellgut or Roggensauerteig as well — don't go through the machine translation but are put in as the target language's own term (scald, soaker, sourdough starter, bulk fermentation …). An older translation that still had such a word wrong is translated afresh when the recipe is opened.
- **The original is never overwritten.** The original is the language the recipe is written in — not the language your app happened to be set to. The app reads that off the recipe text, so a French recipe is kept as a French original even if someone entered it in a German-language app.

### Taking a copy of a recipe

The recipe page has a **Save as my own recipe** button. It puts a complete copy — image, components, ingredients, and steps included — into "My recipes". Only that copy can be edited. If a copy already exists, it stays as it is — your changes and its baking history included. The public recipe never overwrites it, not even when you save or plan it again.

The app confirms with **"Recipe was saved"** and a note that you can edit the copy without changing the public recipe. If saving fails, an error message appears instead — nothing disappears silently.

### Editing a recipe of your own

Recipes that came from *your* account can be changed right in the recipe database: **"…" menu** at the top right → **Edit recipe**. The form matches the one for entering a recipe: image, name, description, link, tags, components with their ingredients, and steps. Components, ingredients, tags and steps can be added and deleted. **Save** writes the changes to the database, **Cancel** discards them; until then the recipe on screen stays as it was.

Note:

- What you edit is always the **original**, in the language the recipe was written in — even if you're looking at a translation right now. Existing translations are discarded and created anew the next time a language is chosen.
- Start times, total duration and total weight are recalculated when saving.
- A new image replaces the old one in the database.
- The version under "My recipes" on the device is unaffected; it remains a recipe of its own.

For recipes by other authors the entry doesn't appear — except for administrators (see below).

### Reporting, blocking, deleting

Through the **"…" menu** at the top right:

- **Report recipe** — you choose a reason (objectionable/offensive, spam, copyright infringement, other). The report goes to the operator for review, and the recipe is hidden **from every user immediately**, not only after the review. It becomes visible again only if an administrator releases it.
- **Block author** — every recipe by that author disappears from your list. This applies **on your device only**; other users still see them.
- **Edit recipe** — appears only for recipes that came from *your* account (see above).
- **Delete my recipe** — likewise only for your own recipes. The recipe is removed from the database for good.


So the two differ in reach: **blocking is local, reporting affects everyone.** Both can be undone under *Settings → Moderation* (see [chapter 14](#14-settings)).

### Administrator function

If you're signed in as an administrator (see [chapter 14](#14-settings)), you can remove any public recipe — intended for moderating reported content. There are three ways to do it: the **Delete recipe (admin)** entry in the recipe's ⋯ menu, the button of the same name at the bottom of the recipe page, and in the recipe database a swipe to the left across the row. Each asks for confirmation first; in the list the question names the recipe. The recipe's image is removed from storage along with it. Through **Edit recipe** in the same menu you can also correct a public recipe — a typo, say, or a wrong quantity — without deleting it. An administrator has no access to the recipes other users keep on their devices; they aren't shared, so they aren't a moderation matter either.

**Reported recipes** stay visible in the list for administrators while they're hidden from everyone else. At the bottom of the recipe page it then says "This recipe has been reported and is hidden from all other users." If the report is justified, delete the recipe. If it isn't, **Unhide recipe** makes it visible to everyone again at once.

---

## 6. My recipes

My recipes are the recipes on your device: the ones you created, imported, or copied from the database. You find them on the **Recipes** tab with the filter chip **Local** (see [chapter 5](#5-recipe-database)); switch the chips **Published by me** and **Public** off and the list is your own recipes alone.

![List of my recipes with image, name, and tags](images/en/eigene-rezepte.png)

Where only your own recipes come into question — the empty screens of the shopping list and the baking history — **Open my recipes** opens a list of just those. While it is empty, it offers the two ways to a first recipe right there: **Open the recipe database** and **Create new recipe**.

### Searching and filtering

- **Search field** with a **Name / Tags** switch.
- **Filter symbol** at the top right: pick a minimum rating (All ratings, 1–5 stars and up), show or hide variants and set the **facets**. While a filter is active, the symbol is shown filled; **Reset filters** clears all facets at once. In a narrow iPad window (Split View, unfolded iPhone Duo) the filter sits in the **More (⋯)** menu as the submenu **Filter recipes**.

The search ignores capitalisation and matches partial words: "rye" finds "Rye bread", and for tags a fragment of the keyword is enough. Search, rating and facets can be combined; what matches all of them stays.

#### Facets

The app reads each recipe from its ingredients and steps – there is nothing to enter. Each facet has a submenu:

| Facet | Choices | How the app knows |
|-------|---------|-------------------|
| **Duration** | Under 4 hours, 4 to 12 hours, Overnight, Several days | Total time of the steps from the first to the last |
| **Day flow** | Start in the evening, bake in the morning; Start in the morning, bake in the evening; Done in 2 hours | If the last long rest (6 hours or more, such as the proof in the fridge) leaves at most 3 hours afterwards, "Start in the evening, bake in the morning" fits – in the morning the bread only needs shaping and baking. "Start in the morning, bake in the evening" are recipes up to 10 hours without such a rest; "Done in 2 hours" up to 2 hours. |
| **Leavening** | Pure sourdough, Yeast, Sourdough and yeast | Ingredients and component names: sourdough, starter, levain, lievito madre, yeast, poolish, biga … |
| **Flour** | Mostly wheat, rye, spelt or wholemeal | The flour with the largest share; wholemeal from half the flour |
| **Dough yield** | Firm (under DY 165), Medium (DY 165 to 180), Soft (from DY 180) | The dough yield of the whole recipe, see [chapter 15](#15-units-amounts-and-serving-sizes) |
| **Equipment** | Baking stone, Loaf tin, Proofing basket, Pot | The wording of the steps ("bake in the pot", "into the loaf tin", "into the basket", preheating with a stone) |
| **Baking history** | Never baked, Not baked for a while (over 90 days), Favourites (baked at least twice and 4 stars) | Your baking history – own recipes only |
| **Little work** | Switch | At most 30 minutes of hands-on time, everything else is rest and oven |

The five **collections** are nothing but facets that have been set: "For tomorrow morning" is the day flow "Start in the evening, bake in the morning", "Quick bread" is "Done in 2 hours", "Pure sourdough" is the leavening, "Not baked for a while" and "Favourites" are the baking history. If you open the filter menu after tapping a chip, you see the facet set there and can add more – the chip is then no longer marked, because the selection is now more than the collection.

**Your own collections.** A combination you need often – say "Pure sourdough" with "Pot" and "Little work" – is saved from the filter menu with **Save collection** under a name. It appears as a chip with a bookmark after the five presets and works like them. A long press on the chip offers **Rename** and **Delete**. The collections stay on the device; they hold only the facets, not the search text or the minimum rating. Your own collections and **Finish by …** are part of BakePlanner Pro; the facets and the five preset chips are free.

**Finished by.** In the filter menu, **Finished by …** takes the date and time the bread is to be ready. The list then shows only recipes that can still be made from now on, ordered by the start they need, and writes it under each recipe: "Start today 17:45", "Start tomorrow 06:10". It is worked out as in the plan sheet's "Finished by" mode: with the preheat time and, for a baking stone, the stone's preheat time from the settings. A moon after the start means a step falls outside the day's start and end. The chosen target is the first chip above the list; a tap changes it, **Clear** in the dialog or **Reset filters** removes it. A long press on one of your own recipes offers **Start today 17:45** – that opens the plan sheet with exactly this start. The collection **For tomorrow morning** sets the target along with it: tomorrow at 7:30, or half an hour after the day's start when that is later.

**Spotlight.** Your own recipes are in the iPhone's search as well: swipe down on the Home Screen, type "Landbrot", and BakePlanner opens the recipe directly. They are found by name, tags and description; the index is refreshed at launch and whenever a recipe changes.

### Deleting a recipe

Swipe the row left → **Delete**. A confirmation follows, naming the recipe, so that an accidental swipe can't destroy one. Deleting a recipe also deletes its components, ingredients, processing steps, and baking-history entries.

Steps already scheduled for that recipe do stay in "Scheduled steps", though — delete them separately there if you no longer need them.

### The page of your own recipe

A recipe opens as **one continuous page**, from top to bottom:

1. **Image and name** — tap the image to enlarge it. Below them the **rating** (see [chapter 9](#9-editing-a-recipe)) and the description.
2. **Serving size** (0.5 / 1.0 / 1.5 / 2.0) or **dough weight**, the **weight in grams** calculated from it, — if one is stored — the **Recipe link**, **Share recipe** and **Export recipe**: sharing produces a PDF with the picture, the components and their ingredients, the total ingredients and the processing steps at the serving size currently chosen, and offers it in the share sheet — Messages, Mail, printing or "Save to Files"; exporting writes the recipe to a file (see [chapter 14](#14-settings)). Below it stands **"Dough yield 172 · hydration 72 %"**, the dough yield and hydration over all components; a tap opens the breakdown (see [chapter 15](#15-units-amounts-and-serving-sizes)). For recipes planned on a rhythm, "Next bake" or "Next feeding" follows.
3. **The buttons** — see the table below.
4. **Total ingredients** — every ingredient across all components, added up. This list is meant for shopping and weighing. Water is deliberately left out, as are ingredients that are themselves an intermediate product of a component ("sourdough" as an ingredient of the main dough, say) — otherwise amounts would be counted twice.
5. **Components** — sorted by number, each with its ingredients at the chosen serving size. Flour and starter lines can be tapped (see [chapter 15](#15-units-amounts-and-serving-sizes)).
6. **Last time** (once the recipe has been baked) — how the last bake of this recipe went: room and dough temperature, the actual bulk and final proof, flour, crumb/oven spring and the comment from the baking history, with its date. **Add details** opens the entry; if nothing has been noted yet, the card asks and offers **Note it now**. Only a bake that has already happened counts — the entry created when reminders are set lies in the future until the bake ends.
7. **Processing steps** — a table of number (No.), description and duration; the start times are only worked out by the baking instructions.
8. **Previous bakes** — every baking-history entry, newest first, each with its date, the measurements in one line and the comment; an entry still ahead is marked "planned".

| Button | Purpose |
|--------|---------|
| **Plan** | Baking instructions with the schedule and "Set reminders", as a sheet over the recipe (see [chapter 7](#7-baking-instructions-and-reminders)); for starter recipes it plans the feeding |
| **Shopping list** | Put this recipe's ingredients — at the chosen serving size — on a shopping list (see [chapter 13](#13-shopping-list)) |
| **Log a bake** | Record a bake with date, comment, photos and measurements (room and dough temperature, proofing, flour, crumb); not for starter recipes |
| **Starter Diary** | Only for starter recipes, in place of "Log a bake" (see [chapter 9](#9-editing-a-recipe)) |
| **Edit** (top right) | Edit the recipe, as a sheet over the recipe (see [chapter 9](#9-editing-a-recipe)) |

Serving size and dough weight apply to the whole recipe: what you set on the page also applies in the baking instructions and to the shopping list.

The schedule is only worked out once you tap **Plan**; **Plan again** in Scheduled steps opens it straight away.

---

## 7. Baking instructions and reminders

This is the heart of the app. **Plan** on the recipe page opens the baking instructions as a sheet over the recipe; the layout is the same for your own and for public recipes. The sheet works with the serving size or dough weight set on the recipe page. **Close** at the top left puts it away; after "Set reminders" it closes by itself with the OK of the confirmation.

![A recipe's baking instructions with processing steps, duration, and calculated start](images/en/rezept-backansicht-zeitplanung.png)

*The baking instructions put each processing step's duration next to its calculated start.*

### From top to bottom

1. **Weight** — the total weight at the chosen serving size. Image, ingredients, components and the "Last time" card are on the recipe page behind the sheet (see [chapter 6](#6-my-recipes)).
2. **Control bar** — see below.
3. **Notes** on the plan — see "What the app objects to in a plan".
4. **Processing steps** — a table of number (No.), description, duration, and calculated **Start**. The last row reads "Done", with the finishing time.
5. **Set reminders**.

### The control bar

| Element | Function |
|---------|----------|
| **Change duration** | A switch. When active, a "Duration" field appears for each step. |
| **Start from / Done by** | Decides how the date below is interpreted. Abbreviated on iPhone in portrait. |
| **Date and time** | The reference point for the plan, selectable from today up to one year ahead. |

**Start from** means: I'm starting at this moment — when will I be done?
**Done by** means: I want to be finished at this moment — when do I have to start? The "Start" column then counts backwards.

Change the time and watch the "Start" column adjust immediately. Nothing is saved yet.

### Adjusting durations

1. Turn on **Change duration**.
2. Enter new durations in the fields in the right-hand column — in minutes ("90") or in hours and minutes ("1:30", "1h 30", "1.5 h", "14 hours"). Empty fields and values of 0 or less are ignored, and the previous value stays.
3. Tap **Apply duration**.

The app then recalculates every start time and the total working time. For your own recipes the new durations are saved permanently; for public recipes they apply only to the current plan.

**Ripening today for starter recipes.** When you plan a starter whose diary holds feedings with time to peak and room temperature (see the starter diary in [chapter 9](#9-editing-a-recipe)), the planning sheet shows a **Ripening today** card: the estimated time to ripeness at the room temperature you set, next to the planned duration of the ripening step, that is the longest one. **Use the ripening time as the duration** sets that step to it; start times and the finish follow, and with "Finish by" the start of the feeding moves accordingly. Like every change of a duration it stays in the recipe until you adjust it again.

**Proofing today for breads.** For a bread the planning sheet recognises the fermentation steps by their wording – a preferment ripening ("let the levain ferment"), the bulk proof before shaping and the final proof after it – and shows a **Proofing today** card: for each phase the planned duration and the duration at the **Room temperature today** you set, which starts at the one noted with the last bake. The arithmetic is that of the starter's ripening estimate: fermentation runs about two and a half times as fast for every 10 °C. The recipe's durations are read as written for 22 °C unless the step names a temperature ("at 26 °C"). Once your bakes recorded the bulk or final proof with the room temperature (see [chapter 12](#12-baking-history)), the app uses those measurements instead ("from 3 bakes"). Steps in the fridge, soakers and the autolyse stay as they are. **Adjust the proof to today's temperature** gives this plan the adjusted durations; the recipe stays as it is, and **Use the recipe's durations** takes the adjustment back. Where the measured proofs differ from the recipe, the card also offers **Write the durations from the bakes into the recipe**: that stores the measurements, converted to 22 °C, in the recipe for good, like a typed duration. Public recipes get the card without measurements; there the adjustment only applies to the current plan anyway.

### What the app objects to in a plan

Notes appear above the step table as soon as the time you've set produces an impractical plan. They refresh with every change to date, time, or durations — before you tap "Set reminders".

| Sign | Meaning |
|------|---------|
| ⚠️ orange | **A note.** The plan works, but you should know about it. |
| ⛔️ red | **An error.** More bakes would run at the same time than you have ovens. When you set the reminders the app then asks; **Plan anyway** sets the plan regardless — when several doughs fit into the oven together at the same temperature, say. |

Three things are checked:

- **Steps outside your day.** If a step falls before **Start of day** or after **End of day** from Settings, it gets named: "'Stretch and fold' starts on 11/09/26 at 3:07 a.m., which is before the start of day (6:00 a.m.)." With long fermentations that's normal and no cause for concern — it just shows you what you'd have to get up for.
- **Overlapping baking times.** Each oven takes one bake at a time. With one oven (the default), any overlap with another planned recipe is an error: two loaves don't fit in at two different temperatures. If you've entered several **Ovens** in Settings, that many bakes may run in parallel. An overlap that still fits into a free oven is then only reported as a note ("… and therefore needs another oven"); only the bake for which no oven is left is an error.
- **Too short a baking pause.** If less time than the configured **Baking pause** falls between two bakes in the same oven, you get a note. The oven needs that time to change temperature. With several ovens the note is dropped as long as another oven is free during that time — the loaf simply goes into the cold one.

The notes don't prevent anything — you can still set the plan. They only spare you the surprise at three in the morning.

**Suggestions to keep out of the night.** If a step begins before the start of day or after the end of day, the app looks for the nearest earlier and the nearest later time at which every step falls inside your day, and shows them below the notes, for example:

> **Done by Sat, 10 Oct, 1:45 PM**
> 1 hr, 45 min later · Starts Fri, 9 Oct, 6:05 PM · done Sat, 10 Oct, 1:45 PM

**Apply** sets the date and time above accordingly; the recipe stays as it is. The search goes in quarter-hour steps up to a day earlier or later, never before now, and never so that the bake would need more ovens than you have. If there is no such time — say, because the dough takes longer than your day — the app tells you so.

**Suggestions for a baking day.** If the oven time overlaps with another planned recipe or the baking pause is too short, the app likewise looks for the nearest earlier and the nearest later time at which an oven is free: no more bakes at once than you have ovens, and the set pause between them. Times at which no step falls into the night either come first; only when there is none does the app also suggest one with night steps. That is how a second and a third loaf are planned on a baking day without doing the sums yourself.

**Steps with a time window.** Some steps allow leeway: a cold proof of 12 to 18 hours, a bulk proof of 3 to 4 hours. If you enter a **Time window** for a step (At least and At most, see [chapter 9](#9-editing-a-recipe)) or the wording gives one ("12–18 hours in the fridge", "let rise for 30 to 60 minutes"), the baking instructions may stretch or shorten that step within the window. When a step falls into the night or the oven is taken, they first look for the smallest change to such steps – by minutes in all, then by the number of steps – with which everything fits into your day and the ovens, and show it before the date suggestions: "This is how it fits within the steps' time windows: Cold proof: 16h 00m instead of 12h 00m", with start and finish. **Apply** gives this plan the new durations; the date and time stay, and the recipe stays as it is – as with "Proofing today", **Use the recipe's durations** takes the adjustment back. A window read from the wording only counts when the step's duration lies within it; baking and preheating never get one, their time is the oven's. The window in effect is shown on the recipe page in small print under the duration.

### Setting reminders

Tapping **Set reminders** does several things at once:

1. A local reminder is set for **every processing step** at its calculated start time.
2. The step **"turn on the oven"** is inserted automatically — the configured **Preheat time** before the **baking step** (15 minutes by default, adjustable in Settings). The baking step is the one that describes the bake, not necessarily the last one: if "let it cool" follows, the oven is still preheated before the bake.
   - If the recipe names an **oven temperature**, it is added, for example "Turn on the oven (250 °C)". With "bake at 250 °C falling to 220 °C" it is the first one. The temperature may also stand in the step before ("load the bread, oven at 250 °C"). If the step has a temperature as a field under **Oven** (see [chapter 9](#9-editing-a-recipe)), it counts before the wording; likewise a **Falling to** field creates the turn-down step, and **Steam** decides whether it says "release the steam". Two loaves baking at the same time at the same temperature may share an oven in the plan check – a hint instead of an error.
   - If the recipe already has **its own preheating step**, no second one is added. The recipe's own step then serves as the preheating reminder and gets the temperature appended if it doesn't name one yet.
   - If the bake starts in a **cold oven** ("place in the cold oven"), there is no preheat time.
   - If a step names a **baking stone** or steel ("slide onto the hot baking stone", "heat the pizza stone along"), the **Preheat time with baking stone** (45 minutes by default) applies instead of the preheat time – the stone takes far longer than the oven's air.
   - If the baking step names a **falling temperature** ("load at 250 °C, after 10 minutes reduce to 220 °C"), the app additionally inserts **"Turn the oven down to 220 °C"** — at the minute named in the sentence with the lower temperature; "immediately" means at the start of the bake, and without any minute it is ten minutes in. If the step mentions steam, it reads "…, release the steam"; not with "without steam". If the recipe has a **step of its own for releasing the steam** ("Release the steam" 20 minutes after loading), the oven is turned down as the loaf goes in and the inserted step names no steam — the recipe itself says when the steam goes. A convection figure given alongside ("230 °C top/bottom heat, fan 210 °C") does not count as a drop.
3. **"Baking is finished"** is likewise scheduled for the finishing time.
4. Every step lands in **Scheduled steps**.
5. For your own recipes a **baking-history entry** is created with the end date and the placeholder comment "no comment recorded", which you can fill in later.

A confirmation then appears, for example:

> **Reminders were set**
> 12 reminders set.
> Turn on the oven at 4:45 p.m. (250 °C).
> Done at 6:10 p.m.

The texts "turn on the oven", "turn the oven down" and "baking is finished" appear in whichever language is currently active (for public recipes, in the language you're viewing the recipe in).

> **One recipe, one plan — or several.** Tap "Set reminders" while a plan for this recipe is already running and the app asks: **Replace existing plan** discards the old steps together with their reminders and puts the new plan in their place — the way to go when you want to move the bread to another day. **Add as a second plan** keeps the existing plan and sets the new one beside it, for Saturday and Sunday, say. In "Scheduled steps" each plan then gets its own filter chip with its start time, and "Reschedule" and "Delete" only ever act on the selected plan.

> **For Apple Watch: set the reminders on the iPhone.** Reminders are created on the device where you tap "Set reminders", and they stay there. Only an iPhone passes its notifications on to a paired Apple Watch — an iPad isn't paired with the watch and can't do it. So if you plan on the iPad, the baking reminders appear on the iPad alone, even if you're wearing an Apple Watch.
>
> A plan that has already been set can't be moved to another device afterwards — in that case simply set the reminders again on the iPhone. The recipe itself is on both devices through iCloud anyway.

---

## 8. Creating a new recipe

Through **+** at the top right of the **Recipes** tab. The form is laid out from top to bottom.

![The form for creating a new recipe: import from images, from a web page or from text, Publish switch, recipe image](images/en/neues-rezept.png)

*In the recipe form you can import a recipe from images or from a web page, or enter everything by hand.*

### Importing a recipe from images

Right at the top: **Import recipe from images**. It reads in a printed or photographed recipe.

1. **Select images** (up to 10 pages; the order you pick them in is kept) or **Take photo** for a new shot.
2. The chosen pages appear as a list, "Selected pages"; individual ones can be removed with the bin symbol.
3. **"Analyse … image(s)"** starts the text recognition. It runs on the device, shows "Reading image x of y …", and can be cancelled at any time.
4. The app then shows a **summary**: the recognised name, the number of components, ingredients, and steps, plus the recognised components with their ingredients and the recognised schedule.
5. **Check data in the recipe form** transfers everything into the normal recipe form. **Select different images** starts over.

The app reads the images with every source type it knows and keeps the result that fits what's on the page. Straight, legible photos give the best results.

#### Choosing the name yourself

Which line is the heading isn't always visible from a page: a logo, a printed header, and a column heading all look like a title. If the recognised name is wrong, **tap the "Name" row in the summary**. The page then appears exactly as you photographed it, with a frame around every recognised line:

- **Tap** to choose a line as the recipe name.
- **Pinch out with two fingers** to magnify the page up to six times, in case the lines are close together.
- For multi-page recipes, a bar at the top switches between **pages**.
- If the name isn't on the page at all, type it into the **Recipe name** field below.

**Mind the crop.** Cut away everything that isn't part of the recipe: logos, headers and footers, page numbers, web addresses, and stray text from neighbouring articles. That saves you the corrections in the first place. **Handwritten recipes** can't be read reliably by text recognition.

Afterwards be sure to check **amounts, units, temperatures, and times** — nothing is saved until you choose "Save recipe" in the form.

#### Analysis mode: protected cloud AI or on this device only

Above the image selection you choose how the pages are evaluated:

- **Protected cloud AI** — the images are sent in encrypted form through the BackPlaner server to Google Vertex AI (Gemini) and structured there. That usually gives the most complete results, including components such as pre-dough and sourdough. Before the first use the app explains the data transfer and asks for your consent; you can withdraw it under Settings › Privacy & AI.
- **On this device only** — nothing leaves the device. Depending on availability the app uses Apple Intelligence or the on-device text recognition; recognition may be less accurate.

The app remembers the choice for both import routes.

### Importing a recipe from a web page

Below that: **Import recipe from a web page**. It reads a recipe straight from a recipe page on the internet, a baking blog for instance.

1. **Paste the address**: copy the address of the recipe page in Safari and paste it with the paste button next to the field, or type it in. "https://" may be left out; the app adds it.

   **It's quicker straight from Safari:** on the recipe page tap **Share** and choose **BakePlanner**. A small sheet shows the page; **Import** switches to BakePlanner, where the address is already filled in and the analysis starts on its own. That works from any browser and from any app that shares a web address. If BakePlanner doesn't appear in the row of apps, tap **More** and switch BakePlanner on there.
2. Choose the **Analysis mode** as for the image import. With "On this device only" the page text isn't transmitted; without Apple Intelligence the app then takes only the structured recipe data the page itself provides.
3. **Load and analyze page** loads the page on the device, reads out the recipe data and the visible text, and hands them to the chosen analysis. The page's recipe photo comes along.
4. Then the same **summary** appears as for the image import; instead of the recognised source type it shows the source (the web address). **Load a different page** starts over.
5. **Check data in the recipe form** transfers everything into the recipe form. The page's address goes into the recipe's "URL link" field automatically.

**What works well:** most recipe pages and baking blogs provide structured recipe data; then ingredients and steps are almost always right. The cloud AI also separates pre-dough, sourdough, and main dough into components of their own.

**Step numbers:** components that go into the main dough (sourdough, pre-doughs, soakers, and scalds) are each combined by the import into one parallel step 1.1, 1.2, 1.3 … covering mixing and maturing. The main dough's steps follow as 2, 3, 4 …. That way a recipe with four overnight pre-doughs takes twelve hours, not two days. The pre-doughs are started five minutes apart in the plan; the earlier ones get correspondingly more duration so that all are ready together for the main dough. Steps without a recognised duration get one minute.

**What doesn't work:** pages behind a login, a paywall, or nothing but a cookie notice deliver no readable text, and some sites block retrieval by apps. BakePlanner then reports "Unable to import" with the reason. In such cases the text import helps (select the recipe on the page, copy, paste — see below), or the image import of a screenshot of the page.

> **Copyright:** for your own use you may import any recipe. That's why the "Publish" switch starts out off. Only publish other people's recipes with the author's permission.

### Importing a recipe from text

Third: **Import recipe from text**. For recipes that exist as text — from a message, a note, or a web page the web import can't read because it loads its recipe only afterwards (it then reports "no recipe found" although you can see it in the browser).

1. **Copy the text:** on the page, select the recipe from the heading to the last step and copy it. The less that comes along (navigation, comments, ads), the better.
2. **Paste:** tap **Paste** next to "Recipe text" or paste the text into the field. Under **Web address (optional)** you can give the page's address; it goes into the recipe's "URL link" field.
3. Choose the **Analysis mode** as for the image import. With "On this device only" the text doesn't leave the device; without Apple Intelligence the app reads ingredients and steps by fixed rules.
4. **Analyze text** — then the same **summary** appears as for the other import routes. **Paste a different text** starts over.
5. **Check data in the recipe form** transfers everything into the recipe form. The text brings no recipe picture; add one there.

**What the fixed rules need:** headings such as "Ingredients" and "Method" (also "Zutaten"/"Zubereitung", "Ingrédients"/"Préparation"), below them one ingredient with its amount per line ("140 g rye flour") and one step per paragraph. The app recognises components by headings of their own such as "Sourdough" or "For the poolish:". Without headings it tells ingredient lines and sentences apart by their shape. With the cloud AI or Apple Intelligence this matters less. If the text is nothing but a web address, the app points you to the import from a web page.

### Creating a recipe from baker's percentages

Fourth: **Create recipe from baker's percentages** — for everyone who thinks of recipes as a formula. You enter each ingredient as a share of the flour, and the app works out the grams. Part of BakePlanner Pro.

1. Enter the **recipe name**.
2. **Amount:** choose what you give — **Total flour** (say 500 g) or **Dough weight** (say 850 g for a loaf). The app shows the other figure underneath.
3. **Components and ingredients:** a main dough with wheat flour 550 (100 %), water (68 %), salt (2 %) and fresh yeast (1 %) is prefilled. Change names and shares, add ingredients with **Add ingredient** or swipe to remove them. Further components — preferment, sourdough, scald — are created at the bottom with **Add**, and you distribute the ingredients among them. All percentages refer to the **recipe's whole flour**; the ingredients that count as flour carry the **Flour** tag and must add up to 100 percent. Next to every line stand the calculated grams, to a tenth below 10 g.
4. **Next** opens the recipe form with the components in grams and one step "Make …" per component. There you add rests, shaping and baking as for any other recipe, and save.

As long as the flours do not add up to 100 percent, no ingredient reads as flour, or an ingredient has no share, **Next** stays disabled and a note says why. A starter goes in like any other ingredient, as a share; its flour and water are counted into the dough yield later via the starter TA from the settings (see [chapter 15](#15-units-amounts-and-serving-sizes)).

### Storage: on the device or published

The **Save** section holds the **Publish** switch (see also the overview in [chapter 3](#3-key-concepts)). A sentence below it explains what the current position means. The default comes from Settings (*Publish new recipes*).

- **Switch off** — the recipe stays on the device, is backed up through your iCloud, and can be changed at any time.
- **Switch on** — the recipe becomes visible to every user. First comes the question **"Publish recipe?"**, with the note that as its author you can edit or delete it later in the recipe database. The first time round you also have to accept the terms of use (see [chapter 16](#16-privacy-moderation-and-terms-of-use)).

When importing from images or a web page, the switch always starts out off. The symbol on the "Save recipe" button changes along with its position.

### Recipe image

**Photo library** or **camera** (the camera button only on devices that have one).

> **An image is mandatory.** Without a recipe image, saving produces the message "Image required".

### Master data and tags

- **Name** — required. As long as it's empty, "Save recipe" stays disabled.
- **Description** — a multi-line text field.
- **URL link** — an optional link to the source; appears later as "Recipe link".
- **Tags** — type a keyword, tap **+**. Tags are searchable later.

### Components and ingredients

The component first, then its ingredients:

1. Enter the component's number and name (`1` / `Sourdough`, for example) and tap **+**. The number counts up automatically.
2. Below each component the ingredient entry row appears, with these columns:

| Column | Meaning |
|--------|---------|
| **No.** | Sort order within the component |
| **Amount / Weight** | The numeric value of the amount; an empty field means 0 |
| **Unit** | A menu; see [chapter 15](#15-units-amounts-and-serving-sizes) |
| **Ingredient** | The ingredient's name |
| **Z / N** | The fraction — numerator and denominator, 1 / 2 for "½" |

3. **+** adds the ingredient, the bin symbol removes it again. Rows already entered are directly editable.

Only the **name** is mandatory — an ingredient without an amount and unit is allowed ("salt to taste"). Use either amount/weight **or** the fraction fields, not both for the same figure.

### Processing steps

Columns **Step**, **Description**, **Duration**. Enter the duration in minutes ("90") or in hours and minutes: "1:30", "1h 30", "1 h 30 min", "1.5 h", "14 hours" — a number without a unit is minutes, a decimal without a unit is hours. Minutes are what gets stored; once you leave the field it reads "1 h 30 min". After you add one, the step number continues automatically: from a whole number to the next whole number, from a decimal in steps of 0.1. That makes it easy to enter parallel sub-steps as 2.1, 2.2, 2.3.

Remember the rule from [chapter 3](#3-key-concepts): decimal steps run in parallel, whole numbers one after another.

**Stretch and fold during a rest.** If a step describes several folds during a rest — "rest for 3 hours, stretch and fold after 30 and 60 minutes", "store for 8–12 hours at 9 °C and stretch and fold in the first 30 and 60 minutes", or "fold every 30 minutes, 4x" — the app creates one step per fold when you save: 3.1 "Stretch and fold the dough (after 30 minutes)", 3.2 "… (after 60 minutes)" and so on, each with its own reminder. The rest step itself keeps its full duration; the fold steps carry what remains of the rest from their point on. The same happens on import from photos and web pages and when you edit a step (see [chapter 9](#9-editing-a-recipe)). If the fold instruction stands in a step of its own after the rest, it is assigned to the rest mentioned last and expanded there.

### Saving

- **Save recipe** — saves locally or uploads to the database. During an upload, "Recipe is uploading ..." appears; then either "Recipe was saved" or a specific error message.
- **Delete contents** — clears the whole form (without asking).

---

## 9. Editing a recipe

Reachable through **Edit** at the top right of the page of one of your own recipes. The form opens as a sheet over the recipe; the **X** at the top left puts it away again.

### Automatic saving

Changes to **name, description, URL link, tags, and rating** are saved automatically — shortly after you type and at the latest when you leave the screen. There's no confirmation message for it.

A new **recipe image** is saved the moment you choose it.

### Rating

Tap the stars at the top right: 1 to 5 stars. Tapping the first star again resets the rating to 0. The rating is what the rating filter in the lists works on.

### Refresh regularly

For recipes you bake or set up at fixed intervals — the starter above all — there is the switch **Refresh regularly** (**Plan regularly** for breads) with an interval in days (1 to 60). When it is on, the app **plans the next date automatically after the last bake**: as soon as the last bake is finished, the next refresh appears with its reminders under "Scheduled steps". The rhythm hangs on the **start of the first step**: feed your starter at 8:00 today and, at "every 1 day", you feed it at 8:00 again tomorrow — however long the recipe takes, and across a daylight-saving change. The interval always counts from the actual last bake; an earlier or later feeding moves the next date accordingly.

So that a date two weeks away doesn't clutter the lists, "Scheduled steps", the timeline, the "Up next" card, the widget, the Live Activity and Bake Mode hold automatically planned steps back **until two days before they are due**. The reminders themselves still come on time. Steps you planned by hand are not affected.

When the next refresh is due, the recipe page and the edit form show at the top as the line **"Next feeding: Tomorrow 08:00"** ("Next bake: …" for breads) — meaning the start of the first step. While a plan is still running, the line already shows the date after it; before the first feeding it reads "after the first feeding" (for breads, before the first bake, "after the first bake"). For a starter the rhythm counts from the start of its last feeding.

**What makes a recipe a starter** is decided by its ingredients, not by the switch: they give a feeding ratio of starter (or sourdough, levain — the names are equivalent), flour and water, and nothing is baked. A recipe of nothing but those three is always a starter, even when a step mentions the oven ("let ripen in the switched-off oven with the light on", "keep cool until the next bake"). Only an oven temperature or a preheating step — or further ingredients such as salt — make it a bread. A tag such as "Starter", "Feeding" or "Refresh" settles it by hand when in doubt; a "Sourdough" tag is not enough, breads carry it too.

Instead of "Log a bake", starter recipes have the **Starter Diary** button — a starter is fed, not baked. At the top stands the feeding ratio "starter : flour : water", calculated from the recipe's ingredients and therefore not editable by hand. Below it you record, for every feeding, the **time to peak** in minutes, the **room temperature** in °C, optionally the **float test**, and a note on smell and consistency. The previous feedings are listed underneath, newest first — so you can see whether your starter is getting faster or slower.

**Ripening estimate.** Once feedings carry both time to peak and room temperature, the section above tells when the starter is ripe at today's room temperature: "At 22 °C ripe after about 6h 30m, from 4 feedings". You set the temperature with the stepper; it starts at the one noted last. The arithmetic follows the baker's rule that fermentation runs about two and a half times as fast for every 10 °C of warmth: every past feeding is converted to a reference temperature, the middle value taken, and converted back to today's temperature. From three feedings at least 4 °C apart the app learns your starter's own factor from the diary; the last eight feedings count, and a single odd day does not distort the result.

When you plan a starter through **Plan** (or its rhythm comes round), BakePlanner writes an entry into the starter diary at the start of the feeding — "planned" while it lies ahead — and none into the baking history. The last step reminds you: "Feeding finished – record the result in the starter diary". Tap the entry and fill in time to peak, float test and note under **Record result**. The rhythm counts from the start of the last feeding.

### Changing components

- **Adding**: enter a number and name, **+**.
- **Editing**: tap the component's row. "Edit component" opens with the number, the name, and the full ingredient list. There you can add ingredients (**+**), delete them (bin), and edit one by tapping it in the "Edit ingredient" dialogue. **Done** applies, **Cancel** discards.
- **Deleting**: the bin next to the component. The recipe's total weight is recalculated afterwards.

### Changing processing steps

- **Adding**: enter step, description, duration, **+**. The duration as when creating, in minutes or hours ("1:30", "1.5 h"). Start times are recalculated automatically.
- **Editing**: tap the step's row → "Edit processing step". Under **Time window**, **At least** and **At most** say how short and how long the step may take ("12 h" and "18 h"); left empty, the duration is fixed, and a window needs both values in the right order. The sections follow the step: **Time window** appears for steps the planner may stretch, **Oven** for steps that bake, preheat or name an oven temperature – the display switches as you type. Under **Oven** you enter **Temperature** and **Falling to** in °C and choose "With steam" or "Without steam" for **Steam**; left empty, the app reads the oven from the wording as before. For an oven step without stored settings the fields are pre-filled from the wording when you open it ("bake at 250 °C falling to 220 °C with steam" gives 250, 220 and "With steam"); **Done** keeps them, so older recipes can be brought up to date step by step. The settings are shown on the recipe page in small print under the step. What the baking instructions do with it is in [chapter 7](#7-baking-instructions-and-reminders). After **Done** the app recalculates every start time and the working time. If the step describes folds during a rest ("stretch and fold after 30 and 60 minutes"), the fold steps from [chapter 8](#8-creating-a-new-recipe) are created at that point — for an older recipe too, once you open the step and confirm it with **Done**.
- **Deleting**: the bin next to the row.

### Saving manually

The **Save** section holds two buttons. You'll also find them at the top right of the navigation bar, in the menu behind the save symbol.

- **Local** — saves everything including the image, recalculates the total weight, and confirms with "Recipe was saved".
- **Public** — uploads a copy of the recipe so it's visible to every user. The "Publish recipe?" question appears here too.
- **Delete** (top left) — clears the recipe's contents.

After a successful upload, **"Public" is disabled**, because the recipe now has a copy in the database — a recipe is published only once; afterwards you make changes in the recipe database (see [chapter 5](#5-recipe-database)).

If that copy is later deleted (by you or by moderation), the app notices the next time you open the recipe and releases the button again.

---

### Recipe variants

Whoever alters a recipe wants to know later what was different and how it turned out. That is what variants are for: recipes of your own that stay linked to the recipe they came from.

- **Where variants come from:** **Replace flour** and **Adjust starter TA** (see [chapter 15](#15-units-amounts-and-serving-sizes)) create their copy as a variant and note what they changed ("Dinkelmehl 630 instead of Weizenmehl 1050", "TA 170 instead of TA 172"). For everything else, the recipe page offers **⋯ → Create variant** at the top right: you write in a sentence what you mean to change (optional), **Create** copies the recipe as "Landbrot V1", "Landbrot V2" … (the next free number in the recipe's family; deleted numbers are not handed out again) and opens it; the change itself you then make with **Edit**. Copies from earlier versions are linked by the app on its first start to the recipe whose name they carry.
- **On the variant**, below the description, stands **"Variant of …"** with your note; tapping it opens the original recipe. **Compare** shows the differences the app finds: ingredients replaced, added, removed or weighed differently per component, TA, hydration and dough weight before → after, steps with another duration or wording.
- **On the original recipe** a **Variants** card appears at the bottom: per variant its name, the note (or the difference found) and the result from its baking history — how often baked, when last, and with which rating and keywords. So you see at a glance which alteration was better.
- **In the recipe list** a variant shows "Variant of …" under its name. In the filter menu (star symbol) **Show variants** can be switched off; the list then shows only the recipes themselves, their variants are reached from the recipe page.
- If you delete the original recipe, the variants remain as recipes of their own. A variant can be deleted like any recipe.
- The backup file (format version 3) carries the link and the note along; a recipe shared on its own stands alone.

## 10. Scheduled steps (list and timeline)

**Timeline tab.** This is every baking step from every recipe you've set reminders for — in chronological order, across recipes. At the top you switch between two views with **Timeline / List**; the timeline opens first. Automatically planned refreshes (see [chapter 9](#9-editing-a-recipe)) only appear two days before their date.

![Scheduled steps as a list: each card shows the recipe image, start time, duration, and step text; the "Weizensauerteig" card carries an i symbol for the ingredients next to the clock symbol](images/en/geplante-schritte-liste.png)

*In its empty state, the list view also shows where new plans are created.*

### The "Scheduled steps" view (list)

Every step is a card with the recipe image, recipe name, start time, date, duration, and instruction. Tapping one opens the detail view with the recipe, the start, the step number, the duration, and the full description.

**Looking up a component's ingredients** — through the **i symbol** on the card. It only appears on steps that mix one of the recipe's components, such as "Make preferment A" or "Make the final dough". Tapping it opens the ingredients of exactly that component with their amounts, so you can weigh out straight from the plan without opening the recipe. The amounts are at the serving size or dough weight you set the plan with – at ×2 twice the amounts, exactly as in the reminders.

The app recognises such a mixing step by the name of a recipe component occurring in the step text. Steps from the image import know which component they belong to anyway. A step like "Fold the dough" with no component name gets no i symbol.

**Rescheduling a step** — through the clock symbol on the card. The sheet shows the recipe, the step and its current time ("Currently") at the top and, once you have entered minutes, the new one ("New"):

1. Enter minutes (1440 at most, that is 24 hours).
2. Choose a direction: **Earlier** or **Later**.
3. Choose the **affected steps**: **This step only** or **All following steps** (every later step of the same plan moves by the same amount, including "Baking is finished" and steps that begin at the same minute but come after it in the order). A note under the choice spells out what it does.
4. **Apply**.

The matching reminders move along automatically. If the new time would be in the past, the app refuses with "Unable to reschedule".

**Ticking a step off as done** — through the **checkmark symbol** on the card, or by swiping the row to the **right** and tapping "Done". The step leaves the plan, its reminder is removed with it, and the "Up next" bar on the Recipes tab and the widget move on to the next step. It is the same action as "Done" in the notification, just right in the list.

**Deleting:**

- **A single step**: swipe the row left. Its reminder is removed with it.
- **All steps**: the bin button at the bottom right, then "Delete all". That removes every scheduled step **and** every pending reminder — including those for recipes you no longer want to bake.

**Add to calendar.** "Add to calendar" in the share button of the bar at the bottom enters the scheduled steps into your default calendar, one event "Recipe: Step" per step for its duration, at least a quarter of an hour – so the household sees when the oven is taken. With a recipe filter active you can add just that recipe, otherwise all plans. iOS asks for permission the first time; BakePlanner only needs write access and cannot see your events. That is why adding again creates new events instead of changing old ones; after moving steps, add them again if you like and delete the old events in the calendar.

**Baking day sheet.** The share button in the bar at the bottom (it also holds "Add to calendar") offers **Share baking day sheet**: a PDF with every scheduled step, day by day – time, recipe, step, duration and, under a mixing step, the ingredients at the planned amount. For the kitchen wall when several loaves are baked on one day. With a recipe filter active the sheet holds only that recipe. Like the recipe PDF it belongs to BakePlanner Pro.

### The "Timeline" view

The same steps as a **project plan**: every plan gets a lane of its own with the recipe image and name, every step a bar as long as the step takes. The colour says what is to be done — mixing green, resting and proofing grey, shaping purple, oven blue, baking yellow; a legend sits at the top. The bar carries the time and the instruction. Sub-steps that fall inside another step — the stretch and fold during the bulk rest, "Turn on the oven" during the final proof, the turn-down as the loaf goes in — appear as a marker with their time on their step's bar. A checkered flag marks "Baking is finished", a red line the present moment.

The time axis shows the full hours, with weekday and date where the day changes. Short steps get enough room for their time to stay legible; a long stretch without any step — the night the sourdough ripens in — collapses to a hatched band that names what it skips ("22:45 – 08:35 · 10h"). **S / M / L** at the top right sets the scale.

In portrait, time runs top-down: the axis stands on the left, the plans are columns, and you scroll as in the list. In landscape, time runs left to right with a row per plan, on an iPad just as on an iPhone. Steps that run at the same time — the soaker while the sourdough ripens — share the lane side by side. Tapping a bar or a marker opens the step's detail — if the step mixes a component, its ingredients at the planned amount are listed there too. A long press shows the step's full text with its ingredients and offers **Mark as done**, **Reschedule** and **Show ingredients**, like the card in the list. A long press on a lane's header (picture and name) offers **Share baking day sheet**, **Add to calendar** and **Delete** for that one plan — what the list has the recipe filter for. With a mouse or trackpad, hovering over a bar is enough to see the whole text.

![Scheduled steps as a project plan: time axis on the left, one plan per column, bars as long as the steps](images/en/geplante-schritte-timeline.png)

*The switch at the top changes between timeline and list.*

With no steps scheduled, both views read: "No scheduled steps — Set a reminder in a recipe's baking instructions."

### Bake mode

For working in the kitchen there is a **Start bake mode** button: in the list and the timeline the same bar floats over the bottom edge, with the bin for "Delete scheduled steps" beside it and the share icon with **Share baking day sheet** and **Add to calendar**. It opens the current step full-screen in large type: the recipe name and "Step 3 of 12" at the top, below that the time with a countdown ("in 42 min") or "5 min ago" once the step is due, then the step text. If the step mixes a component, that component's ingredients and amounts follow right beneath — the same ones as behind the i symbol.

At the bottom sit large buttons that can be hit with flour on your hands:

- **Back** and **Next** page through every step of the plan.
- **Read aloud** speaks the step and, where present, the ingredients through the speaker in the app language you have set. A second tap (**Stop**) cancels. Speech also plays while the device is muted.
- **Done** removes the step together with its reminder and jumps to the next one.

Bake mode opens on the step that is up right now and respects the list's recipe filter. While it is open, the screen stays on. **Close** at the top right returns to the list.

### Bake mode on the Apple Watch

On a paired Apple Watch, BakePlanner comes as an app of its own: the bake mode for the wrist. It shows the planned steps as the iPhone last passed them on — one step per page, turned with the crown: recipe name, "Step 3 of 12", the step text, the time with "in 42 min" or "for 5 min", and, where the step mixes a component, its ingredients with amounts (for your own recipes). The app opens on the step that is due now.

**Done** takes the step off the plan on the watch at once and reports it to the iPhone, which removes it from the plan together with its reminder — if the iPhone is out of reach right now, it catches up as soon as the connection is back. Shifting and reading aloud stay on the iPhone. The plan comes from the iPhone; steps planned on the iPad do not reach the watch (see chapter 11).

### The "Next baking step" widget

You can see the next step without opening the app: BakePlanner comes with a widget for the Home Screen and the Lock Screen. It shows the same information as the "Up next" bar on the Recipes tab — the upcoming step with its time and a running countdown ("in 1:42:10"), or, once the time has come, **"Due now"** with the elapsed time. Tapping it opens "Scheduled steps" directly.

- **Small**: step text, day and time, countdown.
- **Medium**: the recipe name in addition, and two buttons: **Done** ticks the step off without opening the app – the widget moves on to the next step at once, and the app takes the step out of the plan and removes its reminder the next time it opens. **Postpone** opens the app with the "Shift step" sheet for this step, because the reminders have to move with it.
- **Lock Screen**: as a rectangular widget with step text and countdown, or as a one-line display next to the clock.

To add it: press and hold the Home Screen → **Edit** → **Add Widget** → choose **BakePlanner** → pick a size → **Add Widget**. The widget updates by itself whenever a step starts or falls due, and whenever the plan changes in the app. With no planned steps it reads "No step planned".

The widget uses the device's **system language**, not the app language chosen in Settings.

---

### Controls in Control Center and on the Action button

BakePlanner comes with two **controls** you can place in Control Center, on the Lock Screen or on the Action button (edit Control Center → add a control → BakePlanner): **Step done** ticks off the step that is due right now, exactly like the button on the widget, and **Scheduled steps** opens the app at the scheduled steps. With no step due or within reach, "Step done" does nothing.

### Plan a baking day

**More → Plan a baking day** in the recipe list plans several breads at once. You choose the recipes, the time the last one is to be ready, and the number of ovens (pre-filled from the settings). **Work out the baking day** lays the start times: the bread with the longest bake is ready at the time you want, every further one takes the latest quarter hour before it at which its bake still fits an oven – no more breads at once than ovens, the **pause between bakes** from the settings kept between two bakes in the same oven. Two breads share an oven only while it is set to the same temperature for the whole of their common time – a bread that turns down from 250 to 220 °C does not share with one that still wants 250 °C. And no two doughs are kneaded, folded or shaped at once: when the hands-on work would coincide, the second bread moves forward by quarter hours. Bakes and working steps already scheduled for other recipes count as well.

Each bread shows start, ready time and oven time. A moon warns of steps at night, two hands when hands-on work could not be kept apart after all, a red triangle when no oven becomes free within a day, a red clock when the bread would have to be under way already – then choose a later time. **Plan all** creates the steps, reminders and the baking-history entry for every bread, like "Plan now" on the recipe page; a bread that already has a plan gets the new one in its place. Starter recipes are not offered: they are fed, not baked. Part of BakePlanner Pro.


---

## 11. Reminders on the Lock Screen

> **Android:** reminders arrive as Android notifications with the same actions. Delivery time, alarms and the Lock Screen differ, see [chapter 19](#19-bakeplanner-on-android).

Every reminder appears as a notification titled **"Baking reminder"**, with the subtitle "Press and hold for Done or Reschedule" and the step text as its content.

**Ingredients in the reminder.** If the step mixes a component, the ingredients of that component with their amounts follow below the step text — the same ones that sit behind the i symbol in "Scheduled steps":

> **Baking reminder**
> Make preferment A
>
> Ingredients for "Preferment A":
> • 200 g wheat flour 550
> • 200 g water
> • 2 g yeast

The banner shows only the first lines. Press and hold the notification, or expand it in Notification Centre, to see the whole list. The amounts match the serving size that was selected in the baking instructions when the reminders were set.

**Press and hold the notification** to get two actions:

- **Mark as done** — the step is removed from "Scheduled steps".
- **Reschedule by …** — enter the minutes directly in the notification. A follow-up question then appears: **"Should all following steps of this recipe be moved as well?"** with the options **Only this step** and **All following steps**.

Rescheduling is always counted from **now**: "30 minutes" means "30 minutes from now". With "All following steps", every later step of the same recipe moves by the same difference — so a fermentation stays coherent even when you're running late.

Notifications are shown while the app is in the foreground too.

### Alarms

A notification is quiet when the iPhone is on silent or in a Focus – at three in the morning the bread then stays in the oven. Under *Settings → Baking plan → Alarms* you let selected steps ring as **alarms** as well, which get through silent mode and a Focus: **Oven steps** are "oven on", the step that puts the dough into the oven, and the end of the bake (feeding a starter rings nothing); **All steps** wakes you for every step of every plan. When you turn it on, iOS asks for permission once; if you refuse, the setting falls back to Off and says where to change it.

The alarm shows the recipe and the step, **Stop** and **Done**. Done stops the alarm and takes the step off the plan, reminder included, as on the widget. The alarms follow the plan: move a step and its alarm moves along; delete the plan or tick a step off and the alarm is gone. An alarm whose time has passed is not set again. Alarms exist only on the device that set the plan, like the reminders.

### Live Activity

While a plan is running, BakePlanner also shows the upcoming step as a **Live Activity**: as its own tile on the Lock Screen, and at the top of the display on iPhones with a Dynamic Island. It shows the step text, the recipe name, the time, the step after it ("Then 00:36 · Weizensauerteig …") and a running countdown. When the time has come, the tile switches to **"Due now"** and counts the elapsed time up. A tap opens "Scheduled steps"; on the Dynamic Island a long press expands the view.

The Live Activity appears as soon as a step is less than eight hours away — iOS ends Live Activities after eight hours at the latest, so not earlier. It is updated when you open the app, mark a step as done or reschedule it, and it ends when no step is within reach any more. The first time, iOS asks whether BakePlanner may show Live Activities. Under *Settings → Baking plan → Live Activity on the Lock Screen* it can be switched off altogether.

**Apple Watch.** The baking reminders appear on the watch if you set them on the **iPhone** — the iPhone's notifications are passed on to the paired watch. Reminders set on the iPad stay on the iPad. More on this in [chapter 7](#7-baking-instructions-and-reminders).

### Siri

With dough on your hands you need not touch the device: BakePlanner understands a few phrases through **Siri**, with nothing to set up. Every phrase names the app, which is how Siri knows BakePlanner is meant. German and French Siri accept the name pronounced the English way as well. The phrases exist in German, English and French; Siri understands the ones in its own language.

| What you say | What happens |
|---|---|
| "Next step in BakePlanner" · "What is up next in BakePlanner" | Siri names the upcoming step with recipe and time, or "due now" when it is time. |
| "Step done in BakePlanner" | Marks the due step as done and names the next one. If the step is not due yet, Siri asks first. |
| "Move the next step in BakePlanner later" · "… up" | Moves the upcoming step a few minutes later or earlier. Siri asks "By how many minutes?"; the following steps move along. |
| "When is oven time in BakePlanner" | Names the planned start of baking with its time. |
| "Fed Rye starter in BakePlanner" · "Fed my starter in BakePlanner" | Records a feeding in the starter diary. Without a name Siri asks which starter is meant; the starter recipes count (see [chapter 9](#9-editing-a-recipe)). |
| "Fed all starters in BakePlanner" | Records a feeding for every starter. One recorded within the last hour is skipped. |
| "When did I last feed Rye starter in BakePlanner" · "Last feeding in BakePlanner" | Names the date and time of the last feeding. |

The same commands are listed in the **Shortcuts** app under BakePlanner and can be built into your own shortcuts there. Everything runs in the background; the app need not be open. Whatever Siri changes shows at once in "Scheduled steps", the widget and the Live Activity.

---

## 12. Baking history

### Baking history

**Baking history tab.** Every bake in five views, switched with the symbols under the title; the choice is remembered. **List**: newest first, with date, recipe name, comment and photos. **Gallery**: tiles with the bake's first photo (or the recipe picture as a stand-in), recipe name, date, rating and comment, two across on an iPhone and more on an iPad. **Top list** and **photo cloud** sum the history up per recipe (see below). Search, tags and the rating filter apply in all four. While there is no bake yet, the empty screen explains where entries come from and leads to your recipes.

- **Tap an entry** (row or tile) → baking notes: edit the comment, fill in **Measurements and result** (see below) and add photos through **Photo library**. Photos can be tapped and browsed full size. **Save** confirms with "History was saved".
- **Delete an entry**: swipe the row left.
- **Searching and filtering**: the search field (Name/Tags) and the rating filter at the top right.

In the list and the gallery an entry's measurements appear in one line under the comment, such as "Room 22 °C · Dough 25 °C · Bulk proof 3h 30m · Final proof 1h 00m · Wheat 550 · open, good oven spring".

### Measurements and result

Free text and stars alone are not enough to do better next time. Every entry therefore has a section **Measurements and result**:

| Field | Content |
|-------|---------|
| **Rating** | 1 to 5 stars for this bake, independent of the recipe's stars. Tapping the chosen star again takes the rating back. The stars come first in the history's line of measurements and with the **Variants** of a recipe, so their results can be compared. |
| **Room temperature**, **Dough temperature** | In °C, with comma or point ("22.5"). Empty means "not measured". |
| **Bulk proof**, **Final proof** | The actual duration in minutes; from 60 minutes on the conversion is shown underneath ("= 3h 30m"). |
| **Flour** | The flour used, as free text ("Wheat 550, spelt 630"). |
| **Crumb / oven spring** | Two or three keywords, separated by commas. Below the field are word chips for **Crumb** (open, dense, moist, dry, even, large pores, gummy) and **Oven spring** (good oven spring, little oven spring, torn, stayed flat); a tap puts the word into the field or takes it out again, and a chosen word carries a checkmark. You can add words of your own. |

The number fields have no Return key; **Done** appears next to the field being edited to close the keyboard.

The recipe page shows these details as the **Last time** card (see [chapter 7](#7-baking-instructions-and-reminders)). The bulk and final proof with the room temperature feed the **Proofing today** card the next time you plan, which estimates the proofing times for today's temperature from them and writes them into the recipe on request.

### Recording a bake after the fact

**Recipe → Log a bake.** Choose the baking date (up to 10 years back), write a comment, fill in measurements and result, add photos from the library, **Save**.

An entry is also created automatically when you set reminders in the baking instructions — initially with the placeholder "no comment recorded" and without measurements. After the bake the "Last time" card on the recipe page reminds you to complete it. If you replace or delete the plan before baking, this entry disappears again — unless you have already added a comment, a photo or a measurement. The same applies to the feeding that planning a starter writes into its diary.

### Top list and photo cloud

**Baking history → Top list.** Every recipe you've baked at least once, sorted by the number of bakes — your classics at the top; with equal counts, the most recently baked first. Each recipe shows its rank, picture, name, "baked 3× · last 12 Oct 2026", its rating, the newest photos from the baking histories and, large on the right, the count. A tap opens the recipe. The top list used to be a menu entry of its own; it is the same history, grouped by recipe.

**Baking history → Photo cloud.** The same recipes as a round cloud: every recipe is a circle with the photo of its last bake (or the recipe picture) and the count in its corner. The circle's area follows the count — a recipe baked four times as often gets a circle twice as wide. The most baked recipe sits in the middle, the others nestle around it in a spiral. Larger circles carry the name on a dark band inside; the whole cloud is fitted to the screen. A tap opens the recipe.

![Baking history as a photo cloud: one circle per recipe with the photo of its last bake, the most-baked bread large in the middle, the rarer ones small around it](images/en/backhistorie-fotowolke.png)

*The photo cloud: the more often baked, the bigger the circle.*

---

### Statistics

**Baking history → Statistics.** What your baking history adds up to — always for the entries the search and the rating filter currently show, and only for bakes that are already over (a bake planned in the future does not count yet): The statistics are part of BakePlanner Pro.

- Four figures at the top: **Loaves in total**, **This year**, **Per month** (since the first bake) and, once you have rated bakes, the **Avg. rating** in stars.
- **Loaves per month:** the last twelve months as bars, quiet months stay empty.
- **Baked most:** the seven recipes with the most bakes and their counts.
- **Ratings:** how many bakes got one to five stars — appears once an entry carries stars.
- **Final proof and room temperature:** every bake with a room temperature and a measured final proof as a point, warm kitchens to the right, long proofs at the top — appears from two such entries and shows over time how your dough responds to the temperature.
- **Crumb and oven spring:** how often you gave "open", "dense", "good oven spring" and the other keywords.

The statistics live on the measurements in [chapter 12](#12-baking-history): the more often you record room temperature, proofing times, stars and keywords, the more they show.

## 13. Shopping list

### Putting ingredients on a list

If there is no list yet, the empty screen under "Shopping list" explains the way and leads straight to the recipes with **Open my recipes**.

**Recipe → Shopping list** — for your own recipes and for public ones alike; the sheet opens over the recipe.

1. **Serving size.** At the top sits the same serving-size control as under Details and Bake, with the total weight. The ingredients go on the list **at this factor or dough weight**; at ×2, the doubled amounts. The footer names the factor.
2. **New list**: choose a date, **Create**. If a list already exists for that date, the ingredients are added to it.
3. **Existing list**: switch to "Existing list" and tap **+** next to the list you want. To delete one, swipe the row left.

The confirmation reads "Ingredients were added to the shopping list", and at a factor other than 1.0 adds "The amounts correspond to the factor …". A link to **Show shopping lists** appears afterwards.

### The list speaks your language

The ingredient names on the list are **always in the app's language**, even when the recipe is German or French. For public recipes the app uses the translation it already has; otherwise it translates the names on the device when the list is created — "Translating ingredient names …" shows briefly. The glossary of baker's terms applies (see [chapter 5](#5-recipe-database)). If the translation fails, for instance without a language pack and without a connection, the names go on the list in the recipe's language and the confirmation says so. This also lets ingredients from a German and an English recipe merge on one list.

### What makes it onto the list — and what doesn't

The app filters deliberately, in every language:

- **Left out** are **water** (including mixing water, Wasser, eau), **salt** (including sea salt, Salz, sel) and everything you make yourself: **sourdough starter, sourdough, levain, lievito madre, poolish, biga**. What merely sounds like it is bought — rose water, coconut milk, salted butter, dried sourdough or sourdough extract stay on the list.
- **Left out** are ingredients with no unit or no usable amount.
- **Eggs are counted by the piece**, in every language: "120 g eggs" become "2 pcs eggs", rounded up, at ×2 four pieces.
- **Identical ingredients are combined.** Temperature details are stripped from the name in the process: "milk 30 °C" and "milk" count as the same ingredient, as do "fresh yeast" and "yeast", "eggs" and "egg", "Weizenmehl Type 550" and "Weizenmehl 550" or "walnuts, chopped" and "walnuts". Capitalisation and umlauts make no difference.
- **Units are converted** when they share the same base unit: 0.5 kg + 200 g are added together, and so are tablespoons and millilitres. Grams and millilitres stay separate.

### Viewing shopping lists

**Shopping lists tab.** Each list shows its date, the recipes it contains, and below them the ingredients with amount and unit — **grouped by shelf**, in the order of a walk through the shop: flour & grains, dairy & eggs, baking supplies, nuts, seeds & dried fruit, fruit & vegetables, spices & herbs, oils, fats & liquids, other. The app reads the shelf off the ingredient's name, so older lists are grouped too.

Tapping an ingredient opens **Change amount**: amount, unit and fraction then apply to this list, the recipe stays unchanged; the ingredient can be removed there as well. The bin symbol next to the row removes it directly. **Delete** removes the whole list after a confirmation.

**Package sizes.** The list names what you actually buy in the shop: before the ingredient stands the usual package covering the need, the need itself in brackets – "1 kg Weizenmehl 550 (200 g)", "42 g fresh yeast (6 g)", "6 pieces eggs (2 pcs)". Flour comes in 1 kg, 2 kg and 2.5 kg (several packages above that), flakes, semolina and meal from 500 g, fresh yeast in a 42 g cube, dry yeast in a 7 g packet, baking powder in a 15 g packet, butter in 250 g, salt and sugar in 500 g and 1 kg, honey, syrup and malt in 250 g and 500 g, quark and yoghurt in 250 g and 500 g, nuts, seeds and dried fruit from 100 g, eggs by 6 or 10. Liquids, spices, fruit and vegetables keep showing the need; when the need is a package, the brackets are left out. "Send to Reminders" takes the lines as they read.

### Pantry

**More → Pantry** in the recipe list keeps what you have at home: flours, seeds, yeast – on the same shelves as the shopping list. Each item has a name, an amount in g, kg or pieces, a **best-before date** if you like, and a note. **+** adds an item; for the name the app suggests the ingredients of your recipes, so the pantry and the recipes mean the same thing ("Weizenmehl 550"). A tap on an item edits it, a swipe to the left removes it.

Items that expire within the next 14 days or already have sit at the top under **Use up soon**, marked orange or red.

**From the shopping list into the pantry.** Every line of a shopping list has a parcel symbol next to the bin, **Move into the pantry**, and the list's header one for **Bought**. Both open the sheet **Bought**: each line shows the need ("Needed: 200 g") and the amount bought in g, kg or pieces, prefilled with the package from the list – enter what you actually bought; switching from g to kg converts the number. **Book** adds every line with an amount to the item of the same name – or creates it; grams and kilograms are added up – and takes it off the list. A line with an empty amount stays on the list; when nothing is left, the list is deleted.

**Matched against the recipes.** As soon as the pantry holds anything, a recipe's page shows a **Pantry** card: "All 5 ingredients are in the pantry" or "3 of 5 ingredients in the pantry" with what is missing – "200 g Roggenmehl 1150 missing" –, worked out at the serving size chosen. Water, salt and starter do not count; they are not on the shopping list either. Ingredients meet by name – "fresh yeast" and "yeast", "eggs" and "egg", "walnut kernels" and "walnuts", "sea salt" and "salt" count as the same, "dry yeast" or "egg yolk" do not; flour types count alike ("Weizenmehl 550", "Type 550", "T550"), "Weizenmehl Vollkorn" is "Weizenvollkornmehl", and words such as "fresh", "chopped", "toasted" or "softened" make no difference; use the suggestions from the recipes when adding items, then they match. Amounts from 1000 g are shown in kilograms. The full backup (see [chapter 14](#14-settings)) takes the pantry along; reservations belong to the device's plans and stay out.

- **Shopping list:** the form has the switch **Deduct pantry** (on by default). What is in the pantry stays off the list, partial amounts are reduced – 500 g needed, 300 g there, 200 g on the list. If everything is there, the app says so instead of creating an empty list.
- **Filter and collection:** the filter menu has the switch **From the pantry**, the chip row the collection of the same name: only recipes whose ingredients, at the stored amount, are completely there.
- **When planning – reservations:** as soon as you plan a bread ("Plan now", baking day, recurring plans), the app reserves what it will use at the planned serving size. The stock itself stays, but **available = stock − reservations**: the recipe card, the shopping list and the collection "From the pantry" work with what is available, and on the baking day you see before "Plan all" what is missing for all chosen breads together. In the pantry an item reads "250 g of it reserved". When a plan is deleted or replaced, its amounts are free again at once. When a plan reaches its end ("Bake finished"), the reservation becomes a deduction: the stock drops. That happens the next time the app comes forward or when you mark a step done in bake mode – also for plans another device created or deleted.
- **Recent deductions:** the pantry lists the deductions of ended plans. **Undo** books the amount back if a bread was not baked after all.
- **After baking without a plan:** when you record a bake for a recipe that had no plan, the app asks **Deduct from the pantry?** and shows what comes off which item – with two bags of the same flour, from the one that expires first. A planned bread is not asked again; it is booked through its plan.

**Shelf life.** Under *Settings → Pantry → Reminder before expiry*, BakePlanner sends a notification 14 days before an item's best-before date, at 9 in the morning. The collection **Use up the pantry** in the chip row – also a switch in the filter menu – shows the recipes that use something of what expires soon or already has, the recipe using most first. Under each one stands what it uses up: "Uses 450 g Roggenmehl 1150, best before 20.11.2026".

Like recipes and shopping lists, the pantry lives in your iCloud, and it belongs to BakePlanner Pro.


---

## 14. Settings

> **Android:** some settings do not exist there, the language is chosen in the Android settings, and there is no Pro — see [chapter 19](#19-bakeplanner-on-android).

**Recipes tab → More (⋯) → Settings.** The settings apply on all your devices: they travel through iCloud, together with the saved collections and the custom units. Only the language, the consent to the cloud analysis and the list filters stay per device.

![BakePlanner's settings: General with language and the "Publish new recipes" switch, Recipes with default serving size, detail view, baker's percentages, sourdough starter TA 200, lievito madre TA 150, and custom units, Translation with automatically translating public recipes; Baking schedule begins below](images/en/einstellungen.png)

*Settings bring together language, defaults, and the parameters for the baking plan. The Privacy & AI, Moderation, and Account sections follow further down.*

**Send to Reminders.** The checklist button next to "Delete" (**Send shopping list to Reminders**) sends every item of the list to the Reminders app, into a list of its own called "BakePlanner", created the first time. There the list can be shared with the family and ticked off while shopping. iOS asks for permission to Reminders once; every send creates new items.

### General

| Setting | Description |
|---------|-------------|
| **Language** | System language, German, English, or French. Affects the interface as well as date and time formats. |
| **Publish new recipes** | The default position of the **Publish** switch when creating a recipe. Default: off — new recipes stay on the device. |

### Recipes

| Setting | Description |
|---------|-------------|
| **Default serving size** | The value recipes open with: 0.5 / 1.0 / 1.5 / 2.0. Default: 1.0. |
| **Use detail view** | On: the components and steps of every public recipe are loaded along with the list — recipes open faster, but the first load takes longer and uses more data. Off: details are loaded only when you open a recipe. Default: on. |
| **Show baker's percentages** | Adds each weighed ingredient's share of the component's flour in the component view (see [chapter 15](#15-units-amounts-and-serving-sizes)). Default: off. |
| **Sourdough starter** | Dough yield of your starter, used to split an amount of starter into flour and water when the recipe does not state its TA. 120 to 300 in steps of five. Default: TA 200. |
| **Lievito madre** | The same for lievito madre. Default: TA 150. |
| **My starter TAs** | The dough yields you keep your starters at, separated by commas ("190, 210, 220"). They are offered as quick picks when adjusting the starter TA (see [chapter 15](#15-units-amounts-and-serving-sizes)). Default: 150, 180, 200, 220. |
| **Custom units** | Shows how many you've created and leads to managing them. See [chapter 15](#15-units-amounts-and-serving-sizes). |

### Backup

The backup is not in the settings but in the recipe list's **More (⋯)** menu, as on Android: the settings hold settings only, the menu holds the actions. Exporting your own recipes is free — your data always stays portable.

| Entry | Effect |
|-------|--------|
| **Export recipes** | Lists your own recipes to tick, with **Select all** at the top right. **Export** writes the selection with its pictures to one file and offers it in the share sheet — for "Save to Files", Mail or AirDrop, say. The switch **With baking history, starter diary and pantry** takes your entries along (photos scaled down to screen size) and the pantry with amounts, best-before dates and notes. Select all with the switch on is the full backup — before changing devices, say; a few recipes without it are a hand-over. |
| **Import recipes** | Reads such a file, or a single exported recipe. Imported recipes arrive as **new** recipes of your own, with the baking history and starter diary from the file; existing ones are never overwritten. If the file holds a pantry, the items your pantry does not have by name are added – existing items stay as they are, even when the same file is read a second time; the message gives both numbers. A backup with baking history, starter diary or pantry needs this version of the app; older ones report that the file comes from a newer version. |

A single recipe is exported on its page via **Export recipe** (next to "Share recipe") — without its baking history and starter diary, which are yours. The file can be handed to someone else, who reads it in through **More (⋯) → Import recipes** — a route outside the recipe database, for recipes out of books, for instance.


The backup file stays under **5 MB** so that it passes through Mail, AirDrop and the share menu without trouble: should it grow larger with the pictures at full camera resolution, the app shrinks the recipe pictures and the baking-history photos step by step as it writes the file — only as far as needed, a small backup keeps its pictures sharp. If that is not enough with a great many photos, the baking-history photos are left out; the recipe pictures always stay. The recipes and entries themselves are not changed.

### Translation

| Setting | Description |
|---------|-------------|
| **Automatically translate public recipes** | Affects only the recipe database. On: recipes are translated into your app language automatically, and the globe symbol doesn't appear. Off: a recipe first shows the language it was written in, and you choose the language yourself through the globe symbol (see [chapter 5](#5-recipe-database)). Default: on. |

### Baking schedule

| Setting | Description |
|---------|-------------|
| **Preheat time** | 0–120 minutes in steps of 5. Used when setting reminders, to place the automatic "turn on the oven" step before the final step. Default: 15 minutes. |
| **Preheat time with baking stone** | 0–180 minutes in steps of 5. Replaces the preheat time when a step of the recipe names a baking stone or steel. Default: 45 minutes. |
| **Baking pause** | 0–120 minutes. The minimum gap between two bakes in the same oven. Default: 10 minutes. |
| **Ovens** | 1–6. How many bakes may run at the same time. The plan check reports an error only when more recipes bake at the same time than there are ovens; the baking pause applies per oven. Default: 1. |
| **Start of day** | 0–23. From when you're available in the morning. Default: 6. |
| **End of day** | Between start of day and 23. Default: 23. |
| **Live Activity on the Lock Screen** | Shows the upcoming step as a Live Activity on the Lock Screen and in the Dynamic Island. Off ends a running one immediately. Default: on. |
| **Alarms** | Off, Oven steps or All steps: which steps ring as an alarm beside their reminder, on silent and in a Focus as well (see [chapter 11](#11-reminders-on-the-lock-screen)). When you turn it on, iOS asks for permission once. Default: off. |
| **Pantry → Reminder before expiry** | A notification 14 days before an item's best-before date, at 9 in the morning (see [chapter 13](#13-shopping-list)). When you turn it on, iOS asks for permission once. Pro. Default: off. |

> **Note:** Only the two **preheat times** actually move steps. **Baking pause, ovens, start of day, and end of day** don't change the plan — the app checks it against them and warns you in the baking instructions when a step falls into your night's sleep or more bakes coincide than you have ovens (see [chapter 7](#7-baking-instructions-and-reminders)).

### Privacy & AI

This shows whether the **protected cloud AI** may be used for recipe imports (see [chapter 8](#8-creating-a-new-recipe)).

| Entry | Effect |
|-------|--------|
| **AI analysis for recipe import** | **Allowed** if you've consented to the cloud AI, otherwise **Local only**. Tapping it opens the **AI privacy** page. |
| **Withdraw consent to cloud AI** | Appears only after you've consented. Withdraws the consent and sets the analysis mode to "On this device only". |

The **AI privacy** page explains which data a cloud analysis transmits, to whom, for what purpose, and what of it remains stored (summary in [chapter 16](#16-privacy-moderation-and-terms-of-use)). You can withdraw your consent there too. It is only ever given during an import itself, after the app has explained the transfer. Withdrawal applies to all future analyses; analyses already completed are unaffected.

### Account

This is where you sign in with Apple. Signing in is **voluntary** and serves two purposes:

- **Author identity.** Without signing in, your published recipes belong to the anonymous identifier of this installation — it's lost with the app and differs on a second device. Signed in, they belong to your Apple Account: you can edit and delete them on every device you're signed in on, and after a reinstall.
- **Moderation rights.** If your identifier has been enabled for it, the label **Administrator** appears as well, and public recipes can be deleted — through the ⋯ menu, the recipe page, or a swipe in the recipe database.

**Neither your name nor your email address is requested** — the app only needs the identifier itself. If your use has been anonymous so far, it carries over when you sign in: recipes already published from this device still belong to you afterwards.

| Button | Effect |
|--------|--------|
| **Sign in with Apple** | Creates or connects your account. |
| **Sign out** | Back to anonymous use. The recipes published under the account stay in the database; you can edit them again once you're signed in again. The app confirms with **"You're signed out"**; it does **not** ask you to sign in again to confirm — that belongs to deleting the account alone. |
| **Delete account** | Removes the account for good (see below). |

**Delete account** asks first. Then this happens:

- The sign-in is undone and the account deleted; the app carries on anonymously.
- **Published recipes stay** visible to every user. They no longer belong to any account, so you can't delete them yourself any more — do that beforehand if you don't want to leave them in the database.
- **Recipes on the device stay.** They belong to the device and your iCloud, not to the account.

This can't be undone. If your last sign-in was a while ago, Apple requires you to sign in again for security — the "Sign in again" sheet appears, and the deletion then continues by itself.

For ordinary baking, for your own recipes, and for browsing the public database, **no sign-in is required**.

### Moderation

This is where you take back what you've hidden in the recipe database.

| Entry | Effect |
|-------|--------|
| **Blocked authors** | How many authors you've blocked. |
| **Unblock all authors** | Lifts every block. Those authors' recipes reappear in the list **immediately**. |
| **Recipes you reported** | How many recipes you've reported. |
| **Clear reports on this device** | Removes the hiding your device has remembered. |

**The difference matters:** blocking is purely a device setting, which is why lifting it takes effect at once. A report, on the other hand, hides the recipe from every user — and only an administrator can undo that. So clearing it here only takes effect *after* the recipe has been released; until then it stays invisible, to you as well.

Both lists apply to this device only and aren't synced through iCloud.

### Help

From here you open the **User manual** (this document), the **Help and contact** page with the e-mail address for questions and bug reports, the **Privacy policy** and the **Legal notice** in your browser. All pages appear in the language the app is set to.

### BakePlanner Pro

Once the purchase is switched on, the settings show the section **BakePlanner Pro** with the price, **Unlock Pro** and **Restore purchases**. Pro is a **one-time purchase**, not a subscription; it applies on every device with your Apple Account and can be shared through Family Sharing. It includes: sharing recipes as PDF, handing recipes on, recurring bake plans, shopping lists, widgets, the Live Activity, the pantry, planning a baking day, your own collections with "Finish by", the baking statistics and recipes from baker's percentages, plus cloud imports without a monthly limit. The core of the app stays free: recipes, the schedule with reminders, bake mode, baking history, the recipe database, the calculators and the backup.

**If you had the app before Pro existed,** you keep what the app could do on the day you installed it – permanently and without buying. Features added later come with the purchase, as for everyone else; the section in the settings says so. This is recognised from the installation date at Apple, so it survives a change of device.

---

## 15. Units, amounts, and serving sizes

### Serving size or dough weight

Every recipe screen scales the amounts in two ways:

- **Serving size** — the factor 0.5 / 1.0 / 1.5 / 2.0 as before; 1.0 is the recipe as stored.
- **Dough weight** — next to it sits a field showing the current total weight as a placeholder. Type a target weight in grams, say 2000, and the app scales every ingredient to that dough weight; the serving-size picker then shows no selection. Tapping a factor clears the field again.

Scaled amounts are rounded the way you weigh them: whole grams from 10 g upwards, one decimal below that ("2.7 g yeast"). Fractions such as "1/2 cube" stay fractions at the factors 0.5 to 2.0 ("3/4 cube") and become decimals at a free dough weight ("0.7 cube"). Serving size and dough weight apply to **the whole recipe** — recipe page, baking instructions and shopping list —, to the ingredients in the reminders you set afterwards, and to the "Replace flour" and "Adjust starter TA" sheets when you open them from the recipe.

### Baker's percentages

Under *Settings → Recipes → Show baker's percentages* the component view adds each weighed ingredient's share of the component's flour, for instance "319 g water · 62 %". Anything with "Mehl", "Schrot", "Grieß", "Dunst", "flour" or "farine" in its name counts as flour, and so do old bread and breadcrumbs (flour that was baked once, as in a scald) — but not linseed meal, flakes, bran or nut and almond flours. A component without flour shows no percentages; neither do pieces or whole components used as an ingredient ("1 whole scald"). The percentages do not change with the serving size.

### Dough yield and hydration

On the recipe page, below the weight, stands the line **"Dough yield 172 · hydration 72 %"**: the dough yield (TA, the German Teigausbeute: flour plus water per 100 g of flour) and the hydration (water per flour) over **all components** of the recipe. A tap opens the breakdown with flour and water in grams, each component's own figure, the starter shares and the ingredients that were not counted.

The baker's convention applies:

- **Flour** is what the baker's percentages count as flour (see above).
- **Poured liquid counts in full**: water, milk, buttermilk, beer, wine, whey, juice and yeast water — even though milk is physically only about 90 % water. That way the figures match what baking books and blogs print. Milk powder and cream of tartar do not count.
- **Sourdough starter is split**: 20 g of starter at TA 200 are 10 g flour and 10 g water; at TA 150 they are 13 g flour and 7 g water. The app reads the TA from the ingredient name when it says "TA 200" or "100 % hydration"; otherwise it takes *Settings → Recipes → Sourdough starter* or *Lievito madre*. Biga (TA 150), poolish (TA 200) and pâte fermentée (TA 165) have their TA by definition. The breakdown says for every starter where its TA came from.
- **Seeds, flakes, fat, eggs, sugar and salt** count neither as flour nor as water. The heavier ones appear in the breakdown under "Not counted", so you can see what the figure leaves out.
- **Each component counts exactly once.** If the main dough lists "gesamter Sauerteig" (the whole sourdough), the sourdough enters through that row, not twice. If it lists "200 g Sauerteig" while the component makes 300 g, two thirds of it count. If the main dough never names the sourdough, the components are simply added up.

The line is absent for recipes without recognised flour. The image import compares the same calculation with the dough yield printed in the book and warns when they differ.

**Pre-fermented flour and notes.** The breakdown also says how much flour ferments before the main dough – in the sourdough, poolish, biga or Vorteig and in the starter itself – in grams and as a share of all the flour; soakers do not count. Below it, **Notes** appear when salt or yeast are far from the usual baker's percentages: salt under 1.5 or over 2.5 percent of the flour (the usual is 1.8 to 2.2), fresh yeast over 2 percent, dry yeast over 1 percent. After an import that catches a misread amount; in a recipe of your own it is just a nudge. A recipe without any salt gets no note.

### Replace flour

No wheat flour 1050 in the house, but spelt flour 630? Flours are swapped **1:1 by weight**; what changes is the water, because every flour absorbs differently. Two ways:

- **In the recipe:** on the recipe page, flour lines can be tapped (arrow symbol behind them). The **Replace flour** sheet shows the recognised flour, lets you pick the replacement by grain and type, and works it out: the component's water change ("+20 g" or "−20 g"), dough yield and hydration before and after. If the component has no water, the app takes its poured liquid (milk, beer); if it has none, it says so. **Create copy with substitution** writes the swap into a new variant of the recipe ("Landbrot V1", see [chapter 9](#9-editing-a-recipe)) and opens it; the original stays unchanged. Only the copy of a public recipe, which has no origin of your own, still carries the date in its name. In that copy the button reads **Apply change**: a second flour or a starter adjustment changes the copy itself, the name stays, and no further copy is created.
- **As a calculator:** **Recipes → More (⋯) → Replace flour** for a free amount — amount, flour in the recipe, replacement flour.

Handling advice comes with it: knead spelt less and consider a soaker or cooked soaker, acidify rye, bake emmer and einkorn in a tin, let wholegrain soak, work extra water in gradually. The water figures are rules of thumb relative to wheat 550 (spelt 630 −4 %, wholewheat +10 %, rye 1150 +12 % …) — flours vary with the mill and the harvest, the dough has the final say.

### Adjust the starter TA

If a recipe asks for "100 g starter TA 150" but you keep yours at TA 210, the sums no longer add up: your softer starter brings less flour and more water. The app evens that out so that **the flour from the starter stays the same**: amount of starter = recipe amount × TA on hand ÷ TA in the recipe, here 140 g instead of 100 g, and the extra 40 g of water come off the water of the same component. Dough yield and total weight of the dough stay as the recipe meant them; with a firmer starter it works the other way round.

- **In the recipe:** on the recipe page, lines with sourdough starter, sourdough or lievito madre can be tapped (drop symbol). The **Adjust starter TA** sheet shows the recognised TA — from the ingredient name or, when none is given there, from Settings, which the sheet points out. Below it you choose the TA on hand: your **starter TAs** from Settings as quick picks, next to them a stepper for any other value. The result names starter before → after, the water change, dough yield and hydration. **Create copy with adjustment** writes everything into a new variant of the recipe ("… V2") and opens it – in a copy that is already adjusted the button reads **Apply change** and changes the copy itself; the new TA then stands in the ingredient name ("Anstellgut TA 210") so the dough yield keeps reading it correctly.
- **As a calculator:** **Recipes → More (⋯) → Starter TA** for a free amount — amount, TA in the recipe, TA on hand.

The adjustment is not offered for lines that stand for a component of the recipe ("200 g sourdough" with a component called sourdough): its TA follows from the component itself. Poolish and biga have their TA by definition. If the component's water does not suffice, the app does not go below zero and names the missing grams. Advice comes with it: a softer starter ferments faster and milder, a firmer one slower and stronger; with a big jump in TA, convert the starter over one or two feedings first.

### Dough temperature

**Recipes → More (⋯) → Dough temperature** works out, by the baker's formula, how warm the **mixing water** has to be for the dough to reach the desired temperature after kneading. You enter the dough's **target temperature**, the **room temperature**, the flour temperature (usually the room's) and, for recipes with a sourdough or preferment, its temperature. The **friction heat** is the warmth the dough picks up from kneading on top: compare the dough temperature you measure after kneading with the target and adjust the value — calibrated once, it holds for every recipe and is remembered. If the sum calls for water that would be too cold or too hot, the calculator says so.

### Dough weight from the tin

**Recipes → More (⋯) → Dough weight** works out how much dough a tin takes and, if you like, opens a recipe scaled to that weight right away.

- **Loaf tin and round tin:** inside measures in centimetres (length, width, height, or diameter and height); with slanted walls take the width at half height. From that the volume and, with the **fill factor**, the dough weight: light wheat and toast about 0.35–0.40 g per ml, mixed bread 0.45, rye, wholegrain and seeds 0.50–0.55. The **dough type** sets the factor, a stepper lets you fine-tune it — after the first bake you know whether your tin takes more or less. Example: 30 × 11 × 8 cm is 2.6 l, about 1,190 g of dough for a mixed bread.
- **Round and oval proofing baskets:** there is no formula here, only the makers' ratings by the diameter (round) or the length (oval) at the rim: 500 g at Ø 18 cm, 750 g at Ø 20 cm, 1,000 g at Ø 22 cm, 1,500 g at Ø 25 cm, 2,000 g at Ø 28 cm; oval 22, 25, 28, 32 and 35 cm. Between the sizes the app interpolates. The dough type corrects the rating: rye and wholegrain dough +20 %, airy wheat dough −10 %.
- **Scale a recipe to this weight** opens one of your recipes with the dough weight as its target weight; ingredients, plan and shopping list use it, the recipe itself stays unchanged.
- **From the recipe:** The scale symbol next to the **Dough weight** field on the recipe page opens the same calculator as a sheet, for public recipes too. **Use as dough weight** puts the result into the field and closes the sheet. The **dough type** is preset from the recipe's flours and seeds: up to 10 % rye, wholegrain and dark flours of the flour counts as light wheat, from 50 % rye, wholegrain and coarse meal or from 15 % seeds, flakes and nuts as rye/wholegrain, mixed bread in between. Flour in preferments and sourdoughs counts, the starter itself does not.

The app remembers the measures and the dough type: one owns a few tins, not a new one every time.

### Available units

You choose the unit from a **menu** (abbreviation – full form). You can't type one in: a unit carries a conversion and not just a name, and the app has to know it. If one is missing, you create it as a **custom unit** (see below).

If a recipe you imported or copied from the database holds a unit the app doesn't know, the field shows a **warning triangle** and a red border. The conversion is then missing, and that ingredient doesn't count towards the total weight.

**On screen and in the recipe.** A recipe always stores the German abbreviation (the "Stored as" column); the app shows it in its own language, with plurals ("2 cups"). Recipes don't change when you switch the language, so the switch applies to every recipe at once, including public recipes by other authors.

**On import** from images or a web page, the app turns English and French units into its own: "tsp", "teaspoon", and "c. à c." become tsp, "tbsp" and "c. à s." become tbsp, "cup" becomes cup, "pinch" and "pincée" become pinch, and so on. Pounds and ounces (lb, oz) are converted to grams straight away, because the German pound in the table (500 g) isn't the imperial one (454 g). Units it doesn't know are kept as they are; they then carry the warning triangle.

**Weight-based (base: grams)**

| Abbrev. | Unit | Stored as | Equals |
|---|---|---|---|
| g | gram | g | 1 g |
| kg | kilogram | kg | 1000 g |
| mg | milligram | mg | 0.001 g |
| pfd | German pound (500 g) | pfd | 500 g |
| pinch | pinch | Pr | 1 g |
| knife tip | knife tip | Msp | 0.05 g |
| bunch | bunch | Bd | 10 g |
| slice | slice | Sc | 25 g |
| roll | roll | Rolle | 275 g |
| pkt | packet | Pck | 11 g |
| handful | handful | Handvoll | 25 g |
| egg | egg | ei | 60 g |
| egg (S) | egg, size S | ei(s) | 50 g |
| egg (M) | egg, size M | ei(m) | 60 g |
| egg (L) | egg, size L | ei(l) | 70 g |
| egg (XL) | egg, size XL | ei(xl) | 80 g |

**Volume-based (base: milliliters)**

| Abbrev. | Unit | Stored as | Equals |
|---|---|---|---|
| ml | milliliter | ml | 1 ml |
| cl | centiliter | cl | 10 ml |
| dl | deciliter | dl | 100 ml |
| l | liter | l | 1000 ml |
| Mass | Mass (1 l) | mass | 1000 ml |
| tsp | teaspoon | TL | 5 ml |
| tbsp | tablespoon | EL | 15 ml |
| cup | cup | Tas | 200 ml |
| splash | splash | Ss | 10 ml |
| dash | dash | Sp | 0.27 ml |
| drop | drop | Tr | 0.067 ml |

**Counted**

| Abbrev. | Unit | Stored as | Equals |
|---|---|---|---|
| pc | piece | St | counted |

### Custom units

If a unit is missing — a "mug", say, or a cube of yeast — you create it yourself: **Settings → Recipes → Custom units**.

| Field | Meaning |
|-------|---------|
| **Name** | The full form, "mug" for instance. |
| **Abbreviation** | What appears in the menu and in the ingredient lists, "mug" for instance. It has to be unused. |
| **Measured in** | **grams**, **millilitres**, or **counted**. |
| **Conversion** | How much one of them holds — around 250 millilitres for a mug. With "counted" the field is dropped. |

Why the conversion is mandatory: the total ingredients, the baker's percentages, and the shopping list all depend on it. Without it, "2 mugs of flour" would count as 2 grams.

Your custom units then sit in the menu alongside the bundled ones. To remove one, swipe the entry left or tap **Edit** at the top right. They apply to this device only and aren't synced through iCloud.

> **Careful when deleting:** recipes that use a deleted unit keep it as text — but the app no longer knows it and shows the warning triangle. Simply create it again in that case.

### Conversion to weight

For the recipe's **total weight**, the app converts volume figures into grams and takes the density of common baking ingredients into account — flour 0.66, water 1.0, oil 0.8, honey 1.3, sugar 1.0, icing sugar 0.6, butter 1.0, cocoa 0.6, starch 0.6, nuts and almonds 0.5, semolina 0.5, milk 1.0, juice 1.0, jam 1.33, for example. The factor is recognised from the ingredient's name: "Weizenmehl 550" is treated as flour.

A cup of flour is therefore counted as 200 ml × 0.66 = 132 g, a cup of water as 200 g.

### Fractions (Z / N)

For figures like "½ egg" or "¾ cube of yeast", use the **Z** (numerator) and **N** (denominator) fields. The app scales fractions with the serving size and reduces them automatically; 2/2 becomes 1, and the remainder is shown as a fraction ("1 1/2").

### Scaling

The serving size affects the total ingredients, the components' ingredient lists, and the displayed total weight. It does **not** affect durations — dough doesn't rise faster just because you make less of it.

**1.0 is always the recipe as stored.** The serving size is purely a display option: it doesn't change the recipe.

---

## 16. Privacy, moderation, and terms of use

### Where your data lives

- **Your own recipes, scheduled steps, shopping lists, and baking histories** live on the device and in your private iCloud database. They're visible only to you and your own devices, not to other users of the app.
- **Public recipes** live in the shared cloud database and are visible to every user of the app. No other recipes are kept in the cloud.
- **Translations** are produced on the device.
- **Recipe import:** with "On this device only", images, page text, and pasted text stay on the device. Only if you've consented to the **protected cloud AI** are the chosen images, or the recipe text (of a web page or pasted by you) and the page's address, sent in encrypted form through a BackPlaner Firebase function (region europe-west1) to Google Vertex AI (Gemini, EU location). There they're processed only to create the recipe draft and aren't stored. All that remains stored is a counter for the hourly usage limit, kept with your pseudonymous identifier. You can withdraw your consent under *Settings → Privacy & AI*.
- The app uses an anonymous identifier so that you can delete your own public recipes and other users can block authors. A user account isn't required for baking. Signing in with Apple is voluntary — it makes your Apple Account the author of your published recipes and enables moderation rights; neither your name nor your email address is requested in the process.
- **You can delete your account yourself at any time** — Settings → Account → "Delete account". Details in [chapter 14](#14-settings).

### Terms of use for public recipes

Before you save a recipe publicly for the first time, you have to accept the terms. The gist:

- A publicly shared recipe is visible to every user of the recipe database.
- There is **zero tolerance** for objectionable, offensive, unlawful, or copyright-infringing content.
- You are solely responsible for the content you share.
- Reported content is reviewed and removed **within 24 hours**.
- Authors who breach the rules repeatedly can be excluded.

Choose **Decline** and nothing is uploaded; the recipe stays in the form and can be saved on the device.

### What you can do about unwanted content

Through the "…" menu in a public recipe: **Report recipe** (with a reason) or **Block author**. Both take effect at once — the report hides the recipe **from every user**, the block only on your device. You can undo both under *Settings → Moderation*. Details in [chapter 5](#5-recipe-database) and [chapter 14](#14-settings).

---

## 17. Frequently asked questions and troubleshooting

**No reminders arrive.**
Check in *Settings → Notifications → BakePlanner* whether notifications are allowed. Check as well whether there are any steps under "Scheduled steps" at all — only tapping "Set reminders" creates reminders. And note: reminders for times in the past aren't triggered.

**Nothing arrives on the Apple Watch.**
Reminders stay on the device where you set them. Only a paired **iPhone's** notifications are passed on to the watch — if you planned on the iPad, the baking reminders appear there and nowhere else. Set the reminders again on the iPhone in that case.

**The recipe database is empty ("No recipes loaded").**
There was no internet connection at launch. Pull the list down to load it again.

**I uploaded my recipe to the database and want to correct it.**
Open the recipe in the recipe database and choose "…" → **Edit recipe** (see [chapter 5](#5-recipe-database)). That works for every recipe that came from your account. The version on the device doesn't change; if you want to bring it in line, edit it separately under "My recipes".

**"Edit recipe" is missing on a recipe I published myself.**
The recipe belongs to a different identifier — the anonymous identifier of another device or of an earlier installation, say. If you published it while signed in, sign in with the same Apple Account: *Settings → Account → Sign in with Apple*, then pull the list down once.

**I tapped "Set reminders" twice by mistake.**
On the second tap the app asks whether the new plan should replace the existing one or be added beside it. If you chose "Add as a second plan" although you only wanted one, select the surplus plan under "Scheduled steps" via its chip and delete it with the bin button via "Delete only '…'".

**I want to schedule the same recipe for two different dates.**
Set the reminders for the first date, then set the second one and tap "Set reminders" again: the app asks whether the new plan should replace the existing one or be **added** beside it (see [chapter 7](#7-baking-instructions-and-reminders)).

**The total weight is wrong.**
Usually it's a unit the app doesn't know — the unit field then shows a **warning triangle** — or an ingredient without a unit. Check the ingredients under "Edit" and choose the unit from the menu. If it isn't there, create it under *Settings → Recipes → Custom units* (see [chapter 15](#15-units-amounts-and-serving-sizes)).

**An ingredient is missing from the shopping list.**
Water, salt and everything you make yourself (sourdough starter, sourdough, poolish, biga) are left out deliberately — in every language —, as are ingredients without a unit or without an amount. See [chapter 13](#13-shopping-list).

**The amounts on the shopping list don't match the recipe.**
The list takes over the serving size or dough weight set in the recipe — the "Shopping list" sheet shows the factor at the top. Change it there before you put the ingredients on the list.

**A technical term is translated wrongly.**
Baker's terms such as Brühstück or Anstellgut are translated by a glossary in the app (see [chapter 5](#5-recipe-database)). If you still come across a wrong translation, open the recipe once more: an older translation without the glossary's word is created anew. If the mistake remains, report the word — it then goes into the glossary.

**An ingredient is missing from "Total ingredients".**
Water isn't listed there, and neither are ingredients that are themselves the product of a component ("sourdough" as an ingredient of the main dough, say), so that amounts aren't counted twice. They appear in full in the component list below.

**A step starts at an implausible time.**
Check the step numbers: decimal steps (2.1, 2.2) run in parallel, whole numbers one after another. An accidental "3" instead of "2.2" lengthens the total considerably.

**The image import barely recognises anything.**
Photograph straight, well lit, one page per image, and without strong shadows. Recognition is optimised for a two-column layout with a planning example. With an unsuitable source, entering it by hand is quicker.

**Translation fails.**
Translation uses Apple's on-device translation. The first time, iOS has to provide the language pack — that may need an internet connection. Try again later or switch back to the original language.

---

## 18. Known limitations

- **Recipes in the database can be edited only by their author** (or an administrator). Once uploaded, the version on the device and the one in the database are two separate recipes; changes to one aren't carried over to the other.
- **A recipe is published only once.** Afterwards you change the published version in the recipe database, not under "My recipes".
- **Without signing in, authorship is tied to the device.** A recipe published on the iPhone can't be edited on the iPad until both devices are signed in with the same Apple Account.
- **Deleting your account leaves published recipes in the database.** They no longer belong to any account and can only be removed by an administrator.
- **Baking pause, start of day, and end of day** don't move any steps. The app checks the plan against them and warns you. If a step falls into the night, it suggests a different time for the whole plan (see [chapter 7](#7-baking-instructions-and-reminders)); it doesn't lengthen or shorten individual steps.
- **Plans set before this update** carry no plan identifier yet and count together as one plan per recipe. The next "Set reminders" with "Replace existing plan" cleans that up.
- **If you change a recipe after planning it** (steps, durations), the plan already set stays as it is — scheduled steps are a snapshot. "Scheduled steps" then shows a notice at the top, "… has changed since it was planned", with a **Plan again** button that opens the recipe. Only steps added to the recipe afterwards go undetected.
- **The ingredients in a reminder** are fixed when the reminders are set. If you change ingredients or the serving size afterwards, the reminder keeps showing the old amounts; the i symbol in "Scheduled steps", by contrast, always reads the recipe's current state, but scales it by the plan's serving size. Reminders set before this update contain no ingredients yet — planning once more is enough.
- Scheduled steps are matched to recipes by **recipe name**. Two of your own recipes with identical or very similar names can get mixed up over the image and over rescheduling — give them distinct names.
- **Reminders only reach the Apple Watch from an iPhone.** They're created on the device where you tap "Set reminders", and an iPad isn't paired with the watch. An existing plan can't be moved to another device — set it again there.
- **The image import** reads cookbook pages, recipe cards, web printouts, and two-column baking-blog pages with a planning example. How much of it arrives depends on the device's text recognition, though: the same file can yield fewer lines on an iPhone than on a Mac, and with web recipes that use pale grey numbered circles, whole paragraphs are sometimes missing. So always check the steps in the recipe form before you save.
- **The web page import** only reads what a page delivers to an app without signing in. Pages behind a paywall, a login, or a mandatory cookie consent, and sites that block retrieval by apps, can't be read. Without the cloud AI and without Apple Intelligence only the page's structured recipe data is taken; pre-dough and main dough then often end up in one shared component. If a page loads its recipe only afterwards ("no recipe found" although you can see it), select the recipe on the page, copy it, and use **Import recipe from text**.
- **Custom units appear in every language as you created them.** Only the bundled ones are translated.
- **A shopping list keeps the language it was created in.** If you switch the app language afterwards, existing lists stay in the old one; new lists are created in the new one.
- **Blocked authors** are hidden on the device in question only; on a second device they still appear. A **reported** recipe, by contrast, is invisible to everyone until an administrator releases it — to you as well, and even if you clear the report under *Settings → Moderation*.
- **Custom units only apply on the device where you created them.** They aren't synced through iCloud. A recipe using such a unit shows the warning triangle on another device until you create it there too.

---

## 19. BakePlanner on Android

BakePlanner is also available for Android phones and tablets. Recipes, planning, the calculators, baking history, shopping lists and the public recipe database are the same, and this manual covers both versions: terms, procedures and buttons have the same names on Android. The interface follows Android conventions — at the top right there is **More (⋯)**, and recipe pages have **More actions**, where the iPhone shows individual buttons. This chapter lists what is different or missing on Android. As of the Android version 2.4.

### Data, backup and changing devices

- **Everything lives on the device.** Your own recipes, scheduled steps, shopping lists, baking history and starter diary are stored on the Android device. There is **no sync** with other devices — neither with a second Android device nor with an iPhone. Android's automatic backup to Google Drive is switched off for BakePlanner as well, because it is limited to 25 MB and would fail silently with photos.
- **So back up yourself:** **Recipes → More (⋯) → Export recipes**, **Select all**, switch **With baking history, starter diary and pantry** on, **Export** — and put the file in Google Drive, in an e-mail or on your computer (see [chapter 14](#14-settings)). On the new device: **More (⋯) → Import recipes**.
- **Moving between iPhone and Android** works through the same file in both directions. What does not come along: scheduled plans and reminders (plan again on the new device), custom units (create them again) and settings; the pantry comes along – items the new device's pantry does not have by name are added.
- **Photos** for the recipe picture and the baking history are scaled down to screen size on Android as soon as they are picked, not only in the backup file.
- **Recipe database and account** are the same as on the iPhone. **Sign in with Apple** opens Apple's sign-in in the browser and returns to the app afterwards; a recipe published on the iPhone can then be edited from the Android device too.
- **There is no Pro on Android:** every feature is free, there is nothing to buy.

### Interface

- The four tabs **Recipes**, **Shopping lists**, **Baking history** and **Timeline** are the same as in [chapter 4](#4-the-tab-bar). In the Timeline tab you switch between **Timeline** and **List** at the top; **bake mode** starts from there.
- On the page of one of your own recipes the file export is called **Back up recipe** (on the iPhone "Export recipe"); **Share recipe** produces the PDF, **Publish** puts it in the database. Further commands — edit, report, block author, delete — are under **More actions**.
- **Language:** *Settings → General → Language* opens Android's "App language" setting (Android 13 and later). Choose German, English or French there; without a choice the app follows the system language. There is no language picker inside the app.
- **Dark mode** follows the system setting; the **font size** follows Android's "Font size" setting.

### Reminders, alarms and bake mode

- **Reminders** arrive as Android notifications titled "Baking reminder", with the step text and the component's ingredients, and with the actions **Done** and **Postpone by …** including the question about the following steps — as in [chapter 11](#11-reminders-on-the-lock-screen). The app asks for the notification permission when you plan for the first time; without it the plan is set, but no reminders appear, and a hint leads to the Android settings.
- **Delivery time:** Android delivers the reminders through its task scheduler, not as alarms. If the phone lies unused in battery saver for a long time, a reminder may arrive a few minutes later than planned. For steps that must come to the minute, keep **bake mode** open or set an alarm in the Clock app as well.
- **Not on Android:** the real **alarms** for oven steps ([chapter 7](#7-baking-instructions-and-reminders), setting "Alarms"), the **Live Activity** on the Lock Screen, **widgets**, the **Control Center** button, **Siri**, the **Apple Watch** and search via **Spotlight**.
- **Bake mode** is available, with **Read aloud** through Android's text-to-speech. If a voice for your language is missing, install it in the Android settings under "Text-to-speech output" (Speech Services by Google).

### Importing recipes

- **From photos**, Android reads only through the **cloud AI** ([chapter 16](#16-privacy-moderation-and-terms-of-use)); the Android app has no on-device text recognition. If you choose "On this device only", the app explains this and the import does not run. With **Take photo** you photograph page by page, up to ten.
- **From a web page:** share a page from Chrome via **Share → BakePlanner**, and the import opens with the address filled in. Without the cloud AI the app takes only the page's structured recipe data, and **From text** then reads by fixed rules.
- **Recipe picture and baking photos** come from the device's files or straight from the camera.

### What is missing on Android

| Feature | Manual | On Android |
|---------|--------|------------|
| iCloud sync between devices | [chapter 2](#2-system-requirements) | No sync; backup file (above) |
| Automatic translation of public recipes, "Translate recipe" menu | [chapter 5](#5-recipe-database) | Missing. The list shows a stored translation in your app language, otherwise the original language |
| Alarms for oven steps | [chapter 7](#7-baking-instructions-and-reminders) | Missing; reminders as above |
| Baking day sheet as PDF | [chapter 10](#10-scheduled-steps-list-and-timeline) | Missing |
| Steps into the calendar, shopping list to Reminders | [chapter 10](#10-scheduled-steps-list-and-timeline), [13](#13-shopping-list) | Missing |
| Live Activity, widgets, Control Center, Siri, Spotlight, Apple Watch | [chapter 10](#10-scheduled-steps-list-and-timeline), [11](#11-reminders-on-the-lock-screen) | Not planned |
| Settings "Publish new recipes", "Use detail view", "Translate public recipes automatically", "Live Activity", "Alarms" | [chapter 14](#14-settings) | Missing. New recipes start private and go into the database via **Publish** on the recipe page |
| BakePlanner Pro | [chapter 14](#14-settings) | Everything free |
| Create recipe from baker's percentages | [chapter 8](#8-creating-a-new-recipe) | Not yet |
| Baking-history statistics | [chapter 12](#12-baking-history) | Not yet |
| Plan a baking day (More → Plan a baking day) | [chapter 10](#10-scheduled-steps-list-and-timeline) | Not yet; the logic `BakingDayOptimizer` is already in the shared package |
| Pantry (More → Pantry, package sizes on the shopping list, intake from the shopping list with the sheet "Bought", match against recipes, deduction on the shopping list, reservations by plans with the deduction at the plan's end, reminder before expiry, collection "Use up the pantry") | [chapter 13](#13-shopping-list) | Available: **More (⋯) → Pantry** with items, best-before dates and suggestions from the recipes, package sizes on the shopping list, **Bought** for the whole list (button at the top) or one line (in **Change amount** → **Put into the pantry**), the pantry card on the recipe page, **Deduct pantry**, reservations by plans with the deduction at the plan's end and **Last deductions** with undo; the backup carries the pantry. Missing: reminder before expiry, collection "Use up the pantry" and filter "From the pantry", "Deduct from pantry?" after a bake without a plan |
| Facets, preset and own collections, "Finished by" in the recipe list | [chapter 6](#6-my-recipes) | Not yet; the logic `RecipeFacets` and `FinishByPlanner` is already in the shared package |
| Translation of shopping-list ingredients | [chapter 13](#13-shopping-list) | Not planned |

### Requirements

| Item | Value |
|------|-------|
| Android | 9.0 or later; app language separate from the system language from Android 13 |
| Source | Google Play (currently as a closed test) |
| Size | About 55–60 MB download, about 190 MB installed — the app brings its own runtime |
| Permissions | Notifications (reminders), camera (recipe pictures, baking photos, import from photos), internet (recipe database, cloud AI, import from web pages) |
