#!/usr/bin/env python3
"""
Writes the demo data the App Store screenshots show: a backup file
(RecipeExportFile, format version 7) with a handful of own breads and a
starter, each with a picture, a year of baking history with ratings and
measurements, the starter's feeding diary with a feeding under way, and a
stocked pantry. The screenshot run hands the file to the app with the launch
argument -UITestingRestoreBackup (see UITestSupport), which reads it in at
launch the way "Sicherung wiedereinspielen" does.

    scripts/bakeplanner/appstore-demo-data.py <de|en|fr> <output.json> [--now 2026-11-16T09:41]

The pictures come from docs/bakeplanner/appstore/demo/pictures/ (bread photos from
Hans-Peter's recipes, 384 px). Dates lie relative to the moment of the run,
so the history always ends "last weekend" and the feeding under way began
a few hours ago; a fixed seed keeps everything else the same from run to run.
"""

import base64
import json
import os
import random
import sys
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
PICTURES = os.path.join(HERE, "..", "..", "docs", "bakeplanner", "appstore", "demo", "pictures")
REFERENCE_DATE = datetime(2001, 1, 1)  # Foundation's reference date; JSONEncoder's default for Date

# MARK: - Texts

# Ingredient names, by key and language.
INGREDIENTS = {
    "starter":      ("Anstellgut", "Starter", "Levain chef"),
    "water":        ("Wasser", "Water", "Eau"),
    "salt":         ("Salz", "Salt", "Sel"),
    "yeast":        ("Frischhefe", "Fresh yeast", "Levure fraîche"),
    "spelt630":     ("Dinkelmehl 630", "White spelt flour", "Farine d’épeautre T70"),
    "speltWhole":   ("Dinkelvollkornmehl", "Wholemeal spelt flour", "Farine d’épeautre complète"),
    "wheat550":     ("Weizenmehl 550", "Bread flour", "Farine de blé T55"),
    "wheat1050":    ("Weizenmehl 1050", "High-extraction wheat flour", "Farine de blé T80"),
    "rye1150":      ("Roggenmehl 1150", "Dark rye flour", "Farine de seigle T130"),
    "ryeWhole":     ("Roggenvollkornmehl", "Wholemeal rye flour", "Farine de seigle complète"),
    "emmerWhole":   ("Emmervollkornmehl", "Wholemeal emmer flour", "Farine d’amidonnier complète"),
    "potatoes":     ("Kartoffeln", "Potatoes", "Pommes de terre"),
    "sunflower":    ("Sonnenblumenkerne", "Sunflower seeds", "Graines de tournesol"),
    "flax":         ("Leinsamen", "Flaxseed", "Graines de lin"),
    "honey":        ("Honig", "Honey", "Miel"),
    "butter":       ("Butter", "Butter", "Beurre"),
    "milk":         ("Milch", "Milk", "Lait"),
}

COMPONENTS = {
    "levain":   ("Sauerteig", "Levain", "Levain"),
    "main":     ("Hauptteig", "Main dough", "Pâte finale"),
    "scald":    ("Kochstück", "Scald", "Empois"),
    "poolish":  ("Poolish", "Poolish", "Poolish"),
    "soaker":   ("Quellstück", "Soaker", "Trempage"),
    "feeding":  ("Fütterung", "Feeding", "Rafraîchi"),
}

# Instruction templates: key → (de, en, fr). "%d" is filled with a value.
STEPS = {
    "levain":   ("Sauerteig ansetzen und bei Raumtemperatur reifen lassen",
                 "Mix the levain and let it ripen at room temperature",
                 "Préparer le levain et le laisser mûrir à température ambiante"),
    "poolish":  ("Poolish ansetzen und über Nacht reifen lassen",
                 "Mix the poolish and let it ripen overnight",
                 "Préparer le poolish et le laisser mûrir la nuit"),
    "scald":    ("Kochstück kochen, auskühlen lassen",
                 "Cook the scald and let it cool",
                 "Cuire l’empois et le laisser refroidir"),
    "soaker":   ("Saaten mit Wasser quellen lassen",
                 "Soak the seeds in water",
                 "Laisser gonfler les graines dans l’eau"),
    "knead":    ("Hauptteig kneten, zuletzt das Salz einarbeiten",
                 "Knead the main dough, adding the salt last",
                 "Pétrir la pâte finale, incorporer le sel en dernier"),
    "bulk":     ("Stockgare, dabei zweimal dehnen und falten",
                 "Bulk fermentation, with two sets of stretch and fold",
                 "Pointage, avec deux rabats"),
    "shape":    ("Rund wirken und mit Schluss nach oben ins Gärkörbchen legen",
                 "Shape round and place seam side up in the banneton",
                 "Bouler et déposer soudure vers le haut dans le banneton"),
    "shapeLoaf": ("Lang wirken und in die Kastenform setzen",
                 "Shape into a log and put it into the tin",
                 "Façonner en pain long et mettre dans le moule"),
    "shapeRolls": ("Teiglinge zu je 80 g abstechen und rund schleifen",
                 "Divide into 80 g pieces and round them",
                 "Détailler des pâtons de 80 g et les bouler"),
    "shapeBaguette": ("Baguettes formen und im Bäckerleinen gehen lassen",
                 "Shape the baguettes and proof them in the couche",
                 "Façonner les baguettes et les laisser lever sur couche"),
    "proof":    ("Stückgare bei Raumtemperatur",
                 "Final proof at room temperature",
                 "Apprêt à température ambiante"),
    "proofCold": ("Stückgare im Kühlschrank",
                 "Final proof in the fridge",
                 "Apprêt au réfrigérateur"),
    "bake":     ("Einschneiden, bei %d °C mit Dampf einschießen und fallend auf %d °C backen",
                 "Score, load at %d °C with steam and bake falling to %d °C",
                 "Grigner, enfourner à %d °C avec buée et cuire en baissant à %d °C"),
    "bakeFlat": ("Bei %d °C mit Dampf backen",
                 "Bake at %d °C with steam",
                 "Cuire à %d °C avec buée"),
    "feed":     ("Anstellgut, Mehl und Wasser verrühren und bei Raumtemperatur reifen lassen",
                 "Stir starter, flour and water together and let it ripen at room temperature",
                 "Mélanger levain chef, farine et eau et laisser mûrir à température ambiante"),
}

# What the baker noted about a bake, by language.
OUTCOMES = [
    ("Kruste knusprig, Krume offen", "Crisp crust, open crumb", "Croûte croustillante, mie ouverte"),
    ("Etwas zu kurz gebacken", "A little underbaked", "Un peu trop peu cuit"),
    ("Sehr aromatisch, gute Lockerung", "Very aromatic, nice rise", "Très aromatique, belle levée"),
    ("Leicht übergart, flach", "Slightly overproofed, flat", "Légèrement trop poussé, plat"),
    ("Perfekt – das Familienrezept", "Perfect – the family favourite", "Parfait – la recette de la famille"),
    ("Kruste dunkel, Krume saftig", "Dark crust, moist crumb", "Croûte foncée, mie moelleuse"),
    ("Mit Kürbiskernen statt Saaten", "With pumpkin seeds instead", "Avec des graines de courge"),
    ("", "", ""),
]

COMMENTS = [
    ("Sonntagsbrot für die Familie", "Sunday bread for the family", "Pain du dimanche pour la famille"),
    ("Stückgare über Nacht im Kühlschrank", "Final proof overnight in the fridge", "Apprêt la nuit au réfrigérateur"),
    ("Erstes Mal mit dem neuen Gärkörbchen", "First time with the new banneton", "Première fois avec le nouveau banneton"),
    ("Für den Brunch bei Nachbarn", "For brunch at the neighbours’", "Pour le brunch chez les voisins"),
    ("Etwas weniger Wasser, Mehl war frisch", "A little less water, fresh flour", "Un peu moins d’eau, farine fraîche"),
    ("", "", ""),
]

# MARK: - Recipes

def recipe_texts(lang):
    """The breads and the starter: name, summary, tags, picture, components,
    steps and how often it was baked. Weights in grams."""
    L = {"de": 0, "en": 1, "fr": 2}[lang]
    t = lambda triple: triple[L]
    return [
        dict(slug="dinkelkruste", bakes=7,
             name=t(("Dinkelkrustenbrot", "Spelt crust loaf", "Pain croûté à l’épeautre")),
             summary=t(("Mildes Dinkelbrot mit knuspriger Kruste, über Nacht geführt.",
                        "A mild spelt loaf with a crisp crust, retarded overnight.",
                        "Pain d’épeautre doux à la croûte croustillante, pousse lente de nuit.")),
             tags=t((["Brot", "Dinkel", "Sauerteig"], ["Bread", "Spelt", "Sourdough"], ["Pain", "Épeautre", "Levain"])),
             components=[("levain", [("starter", 20), ("speltWhole", 120), ("water", 120)]),
                         ("main", [("spelt630", 400), ("water", 230), ("salt", 12), ("honey", 10)])],
             steps=[("levain", 720), ("knead", 10), ("bulk", 180), ("shape", 10), ("proofCold", 600), ("bake", 45, 250, 220)]),
        dict(slug="bauernlaib", bakes=5,
             name=t(("Großer Bauernlaib", "Large farmhouse loaf", "Grande miche paysanne")),
             summary=t(("Roggenmischbrot mit 1,5 kg, kräftig und lange frisch.",
                        "A 1.5 kg rye-wheat loaf, hearty and long-keeping.",
                        "Miche de seigle et blé de 1,5 kg, rustique et de bonne garde.")),
             tags=t((["Brot", "Roggen", "Mischbrot"], ["Bread", "Rye", "Mixed loaf"], ["Pain", "Seigle", "Pain mixte"])),
             components=[("levain", [("starter", 40), ("rye1150", 300), ("water", 300)]),
                         ("main", [("rye1150", 200), ("wheat1050", 400), ("water", 380), ("salt", 20)])],
             steps=[("levain", 840), ("knead", 10), ("bulk", 60), ("shape", 10), ("proof", 75), ("bake", 60, 250, 210)]),
        dict(slug="roggenkruste", bakes=4,
             name=t(("Roggenkrustenbrot", "Rye crust bread", "Pain de seigle en croûte")),
             summary=t(("Reines Roggenbrot mit Sonnenblumenkernen.",
                        "A pure rye loaf with sunflower seeds.",
                        "Pain de seigle pur aux graines de tournesol.")),
             tags=t((["Brot", "Roggen", "Saaten"], ["Bread", "Rye", "Seeds"], ["Pain", "Seigle", "Graines"])),
             components=[("levain", [("starter", 30), ("ryeWhole", 250), ("water", 250)]),
                         ("soaker", [("sunflower", 80), ("water", 80)]),
                         ("main", [("rye1150", 250), ("water", 180), ("salt", 11)])],
             steps=[("levain", 900), ("soaker", 60), ("knead", 8), ("bulk", 30), ("shapeLoaf", 10), ("proof", 90), ("bake", 65, 250, 200)]),
        dict(slug="kartoffelbrot", bakes=4,
             name=t(("Kartoffel-Sauerteigbrot", "Potato sourdough", "Pain au levain aux pommes de terre")),
             summary=t(("Saftiges Weizenmischbrot mit gekochten Kartoffeln.",
                        "A moist wheat-rye loaf with cooked potatoes.",
                        "Pain mixte moelleux aux pommes de terre cuites.")),
             tags=t((["Brot", "Kartoffeln", "Sauerteig"], ["Bread", "Potatoes", "Sourdough"], ["Pain", "Pommes de terre", "Levain"])),
             components=[("levain", [("starter", 25), ("wheat1050", 150), ("water", 150)]),
                         ("main", [("wheat550", 350), ("rye1150", 100), ("potatoes", 200), ("water", 230), ("salt", 14)])],
             steps=[("levain", 720), ("knead", 10), ("bulk", 150), ("shape", 10), ("proof", 60), ("bake", 50, 250, 220)]),
        dict(slug="baguette", bakes=3,
             name=t(("Baguette mit Kochstück", "Baguette with scald", "Baguette tradition")),
             summary=t(("Knusprige Baguettes mit Poolish und Kochstück.",
                        "Crisp baguettes with a poolish and a scald.",
                        "Baguettes croustillantes au poolish et à l’empois.")),
             tags=t((["Baguette", "Weizen", "Hefe"], ["Baguette", "Wheat", "Yeast"], ["Baguette", "Blé", "Levure"])),
             components=[("poolish", [("wheat550", 150), ("water", 150), ("yeast", 1)]),
                         ("scald", [("wheat550", 25), ("water", 125)]),
                         ("main", [("wheat550", 325), ("water", 80), ("salt", 11), ("yeast", 3)])],
             steps=[("poolish", 720), ("scald", 30), ("knead", 10), ("bulk", 120), ("shapeBaguette", 15), ("proof", 45), ("bakeFlat", 22, 250)]),
        dict(slug="emmer-dinkel", bakes=2,
             name=t(("Emmer-Dinkel-Brot", "Emmer and spelt loaf", "Pain amidonnier et épeautre")),
             summary=t(("Vollkornbrot aus Emmer und Dinkel, nussig im Geschmack.",
                        "A wholegrain loaf of emmer and spelt with a nutty taste.",
                        "Pain complet d’amidonnier et d’épeautre au goût de noisette.")),
             tags=t((["Brot", "Vollkorn", "Emmer"], ["Bread", "Wholegrain", "Emmer"], ["Pain", "Complet", "Amidonnier"])),
             components=[("levain", [("starter", 30), ("emmerWhole", 150), ("water", 150)]),
                         ("main", [("emmerWhole", 150), ("speltWhole", 200), ("water", 240), ("salt", 12), ("flax", 30)])],
             steps=[("levain", 720), ("knead", 10), ("bulk", 120), ("shapeLoaf", 10), ("proof", 75), ("bake", 55, 240, 210)]),
        dict(slug="dinkelbroetchen", bakes=3,
             name=t(("Sonntags-Dinkelbrötchen", "Sunday spelt rolls", "Petits pains du dimanche à l’épeautre")),
             summary=t(("Fluffige Brötchen mit Milch und Butter, am Morgen frisch.",
                        "Fluffy rolls with milk and butter, fresh in the morning.",
                        "Petits pains moelleux au lait et au beurre, frais le matin.")),
             tags=t((["Brötchen", "Dinkel", "Hefe"], ["Rolls", "Spelt", "Yeast"], ["Petits pains", "Épeautre", "Levure"])),
             components=[("main", [("spelt630", 500), ("milk", 300), ("butter", 40), ("yeast", 10), ("salt", 10), ("honey", 15)])],
             steps=[("knead", 12), ("bulk", 90), ("shapeRolls", 15), ("proof", 60), ("bakeFlat", 20, 220)]),
        dict(slug="anstellgut", bakes=0, starter=True,
             name=t(("Weizenanstellgut TA 185", "Wheat starter TA 185", "Levain chef de blé TA 185")),
             summary=t(("Mein Weizenanstellgut, gefüttert im Verhältnis 1:5:4.",
                        "My wheat starter, fed at 1:5:4.",
                        "Mon levain chef de blé, rafraîchi à 1:5:4.")),
             tags=t((["Anstellgut", "Weizen"], ["Starter", "Wheat"], ["Levain chef", "Blé"])),
             components=[("feeding", [("starter", 20), ("wheat550", 100), ("water", 85)])],
             steps=[("feed", 480)]),
    ]


def pantry_texts(lang, now):
    L = {"de": 0, "en": 1, "fr": 2}[lang]
    def item(key, amount, unit, days, note=("", "", "")):
        return dict(name=INGREDIENTS[key][L], amount=amount, unit=unit,
                    bestBefore=seconds(now + timedelta(days=days)) if days is not None else None,
                    note=note[L] or None)
    return [
        item("wheat550", 2.5, "kg", 150),
        item("wheat1050", 1, "kg", 120),
        item("spelt630", 1, "kg", 95),
        item("emmerWhole", 500, "g", 80),
        item("potatoes", 1, "kg", 21),
        item("rye1150", 1.5, "kg", 40),
        item("ryeWhole", 800, "g", 9),
        item("speltWhole", 600, "g", 60),
        item("sunflower", 350, "g", 120),
        item("flax", 200, "g", 200),
        item("yeast", 84, "g", 7, ("2 Würfel", "2 cubes", "2 cubes")),
        item("honey", 400, "g", None),
        item("salt", 900, "g", None),
    ]


# MARK: - Building the file

def seconds(date):
    """A Date as JSONEncoder writes it: seconds since 2001-01-01 UTC."""
    return (date - REFERENCE_DATE).total_seconds()


def picture(slug):
    path = os.path.join(PICTURES, slug + ".jpg")
    with open(path, "rb") as file:
        return base64.b64encode(file.read()).decode("ascii")


def build_recipe(spec, lang, now, rng):
    L = {"de": 0, "en": 1, "fr": 2}[lang]
    components = []
    total = 0.0
    for number, (component_key, ingredients) in enumerate(spec["components"], start=1):
        rows = []
        for index, (key, grams) in enumerate(ingredients, start=1):
            rows.append(dict(name=INGREDIENTS[key][L], number=index, unit="g", weight=grams,
                             normWeight=0, num=1, denom=1))
            total += grams
        components.append(dict(name=COMPONENTS[component_key][L], number=number, ingredients=rows))

    instructions = []
    start = 0
    for index, step in enumerate(spec["steps"], start=1):
        key, duration = step[0], step[1]
        text = STEPS[key][L]
        entry = dict(instruction=text, step=float(index), duration=duration, startTime=start, bakeFlag=False)
        if key == "bake":
            entry["instruction"] = text % (step[2], step[3])
            entry.update(bakeFlag=True, ovenTemperature=step[2], ovenFallingTemperature=step[3], ovenSteam=True)
        elif key == "bakeFlat":
            entry["instruction"] = text % step[2]
            entry.update(bakeFlag=True, ovenTemperature=step[2], ovenSteam=True)
        instructions.append(entry)
        start += duration

    recipe = dict(name=spec["name"], summary=spec["summary"], prepTime=start, totalWeight=round(total, 2),
                  tags=spec["tags"], rating=0, recurrenceIntervalDays=0, image=picture(spec["slug"]),
                  components=components, instructions=instructions)

    if spec["bakes"]:
        recipe["bakeHistory"] = bake_history(spec, lang, now, rng)
    if spec.get("starter"):
        recipe["starterFeedings"] = feedings(now, rng)
    return recipe


def bake_history(spec, lang, now, rng):
    """The bakes of one bread: on weekends mostly, spread over the past
    thirteen months, each with a rating and what was measured."""
    L = {"de": 0, "en": 1, "fr": 2}[lang]
    entries = []
    for _ in range(spec["bakes"]):
        days_ago = rng.randint(6, 395)
        date = now - timedelta(days=days_ago)
        # Move onto the nearest Saturday or Sunday, baked around midday.
        shift = (5 - date.weekday()) % 7
        if shift > 3:
            shift -= 7
        date = (date + timedelta(days=shift)).replace(hour=rng.choice([11, 12, 13, 17]), minute=rng.choice([0, 15, 30, 45]), second=0, microsecond=0)
        if date > now:
            date -= timedelta(days=7)
        rating = rng.choice([3, 4, 4, 4, 5, 5, 5])
        outcome = rng.choice(OUTCOMES)[L]
        comment = rng.choice(COMMENTS)[L]
        entry = dict(date=seconds(date), comment=comment, images=[],
                     roomTemperature=round(rng.uniform(20.0, 24.5), 1),
                     doughTemperature=round(rng.uniform(24.0, 27.0), 1),
                     rating=rating)
        bulk = next((s[1] for s in spec["steps"] if s[0] == "bulk"), None)
        proof = next((s[1] for s in spec["steps"] if s[0] in ("proof", "proofCold")), None)
        if bulk:
            entry["bulkProofMinutes"] = bulk + rng.choice([-30, -15, 0, 0, 15, 30])
        if proof:
            entry["finalProofMinutes"] = proof + rng.choice([-15, 0, 0, 15])
        if outcome:
            entry["outcome"] = outcome
        # Most bakes have a photo: the bread's picture stands in for it.
        if rng.random() < 0.7:
            entry["images"] = [picture(spec["slug"])]
        entries.append(entry)
    entries.sort(key=lambda e: e["date"])
    return entries


def feedings(now, rng):
    """Twelve feedings every second morning, the peaks noted at their room
    temperature, and the latest one under way since this morning."""
    rows = []
    for index in range(12, 0, -1):
        date = (now - timedelta(days=2 * index)).replace(hour=rng.choice([7, 8]), minute=rng.choice([0, 15, 30]), second=0, microsecond=0)
        temperature = rng.choice([20.5, 21.0, 21.5, 22.0, 22.5, 23.0, 24.0])
        # Warmer rooms ripen faster: roughly 10 h at 20 °C, 7 h at 24 °C.
        peak = int(600 - (temperature - 20.0) * 45 + rng.randint(-25, 25))
        rows.append(dict(date=seconds(date), peakMinutes=peak, floatTestPassed=index != 7,
                         roomTemperature=temperature))
    under_way = (now - timedelta(hours=2, minutes=40)).replace(second=0, microsecond=0)
    rows.append(dict(date=seconds(under_way), roomTemperature=22.0))
    return rows


def main():
    arguments = sys.argv[1:]
    now = datetime.now()
    if "--now" in arguments:
        index = arguments.index("--now")
        now = datetime.fromisoformat(arguments[index + 1])
        del arguments[index:index + 2]
    if len(arguments) != 2 or arguments[0] not in ("de", "en", "fr"):
        sys.exit("Usage: appstore-demo-data.py <de|en|fr> <output.json> [--now <ISO date>]")
    lang, output = arguments
    rng = random.Random(2026)
    recipes = [build_recipe(spec, lang, now, rng) for spec in recipe_texts(lang)]
    file = dict(formatVersion=7, recipes=recipes, pantry=pantry_texts(lang, now))
    with open(output, "w", encoding="utf-8") as handle:
        json.dump(file, handle, ensure_ascii=False)
    bakes = sum(len(r.get("bakeHistory") or []) for r in recipes)
    print(f"{output}: {len(recipes)} recipes, {bakes} bakes, {len(file['pantry'])} pantry items")


if __name__ == "__main__":
    main()
