# -*- coding: utf-8 -*-
"""Generuje regionalny cennik PPP (iOS + Android) do Excela dla aplikacji Debatly.

Model: skalowanie w gorę i w dół wokół Polski jako punktu środkowego,
US = Tier 1 (100%), zniżka PPP umiarkowana. Lifetime ~= 2.8x ceny miesięcznej
w każdym kraju (spójny podpis "mniej niż N miesięcy").
Wszystkie ceny to WARTOSCI STATYCZNE gotowe do wpisania w sklepie.
"""
import math
import datetime
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

TODAY = "2026-07-13"

# ---------------------------------------------------------------------------
# 1. KOTWICE CENOWE PER POZIOM (w USD). US = Tier 1.
#    Lifetime ~ 2.8x miesięcznej (jak Twoje 69,99 / 24,99 PLN = 2.80x).
# ---------------------------------------------------------------------------
TIERS = {
    "T1": {"label": "Premium",    "m": 8.99, "l": 24.99},
    "T2": {"label": "Wysoki",     "m": 6.99, "l": 19.99},
    "T3": {"label": "Sredni-wyz", "m": 4.99, "l": 13.99},
    "T4": {"label": "Sredni-niz", "m": 3.99, "l": 10.99},
    "T5": {"label": "Niski",      "m": 3.49, "l":  9.99},
}
US_M = TIERS["T1"]["m"]  # baza do % ceny US

# ---------------------------------------------------------------------------
# 2. WALUTY: kod -> (kurs za 1 USD [orientacyjny, ~sty 2026], miejsca_dziesietne)
#    Kursy sa przyblizeniem - sluza tylko do wyznaczenia ceny lokalnej.
# ---------------------------------------------------------------------------
CUR = {
    "USD": (1.00,   2), "EUR": (0.92,   2), "GBP": (0.79,   2), "PLN": (3.65,  2),
    "CHF": (0.88,   2), "CAD": (1.38,   2), "AUD": (1.52,   2), "NZD": (1.66,  2),
    "SEK": (10.5,   0), "NOK": (10.8,   0), "DKK": (6.90,   2), "ISK": (138.0, 0),
    "CZK": (22.5,   0), "HUF": (355.0,  0), "RON": (4.60,   2), "BGN": (1.80,  2),
    "JPY": (152.0,  0), "KRW": (1360.0, 0), "TWD": (32.0,   0), "HKD": (7.80,  2),
    "SGD": (1.34,   2), "CNY": (7.20,   0), "INR": (86.0,   0), "IDR": (16000.0,0),
    "PHP": (58.0,   0), "VND": (25000.0,0), "THB": (34.0,   0), "MYR": (4.50,  2),
    "TRY": (34.0,   0), "BRL": (5.50,   2), "MXN": (18.5,   2), "CLP": (950.0, 0),
    "COP": (4100.0, 0), "PEN": (3.75,   2), "ZAR": (18.5,   2), "NGN": (1550.0,0),
    "EGP": (49.0,   0), "PKR": (278.0,  0), "BDT": (118.0,  0), "KES": (129.0, 0),
    "MAD": (9.90,   2), "UAH": (41.0,   0), "AED": (3.67,   2), "SAR": (3.75,  2),
    "QAR": (3.64,   2), "KWD": (0.307,  3), "ILS": (3.70,   2), "DZD": (134.0, 0),
}

# ---------------------------------------------------------------------------
# 3. KRAJE: (nazwa PL, ISO2, waluta, poziom, uwaga)
# ---------------------------------------------------------------------------
COUNTRIES = [
    # ---- T1 Premium ----
    ("Stany Zjednoczone", "US", "USD", "T1", "Baza dla auto-przeliczenia Apple/Google"),
    ("Kanada",            "CA", "CAD", "T1", ""),
    ("Australia",         "AU", "AUD", "T1", ""),
    ("Nowa Zelandia",     "NZ", "NZD", "T1", ""),
    ("Szwajcaria",        "CH", "CHF", "T1", ""),
    ("Norwegia",          "NO", "NOK", "T1", ""),
    ("Dania",             "DK", "DKK", "T1", ""),
    ("Szwecja",           "SE", "SEK", "T1", ""),
    ("Islandia",          "IS", "ISK", "T1", ""),
    ("Irlandia",          "IE", "EUR", "T1", ""),
    ("Luksemburg",        "LU", "EUR", "T1", ""),
    ("Singapur",          "SG", "SGD", "T1", ""),
    ("Hongkong",          "HK", "HKD", "T1", ""),
    ("Izrael",            "IL", "ILS", "T1", ""),
    ("Zj. Emiraty Arab.", "AE", "AED", "T1", ""),
    ("Katar",             "QA", "QAR", "T1", ""),
    ("Kuwejt",            "KW", "KWD", "T1", ""),
    ("Arabia Saudyjska",  "SA", "SAR", "T1", ""),
    # ---- T2 Wysoki ----
    ("Wielka Brytania",   "GB", "GBP", "T2", ""),
    ("Niemcy",            "DE", "EUR", "T2", ""),
    ("Francja",           "FR", "EUR", "T2", ""),
    ("Holandia",          "NL", "EUR", "T2", ""),
    ("Belgia",            "BE", "EUR", "T2", ""),
    ("Austria",           "AT", "EUR", "T2", ""),
    ("Finlandia",         "FI", "EUR", "T2", ""),
    ("Wlochy",            "IT", "EUR", "T2", ""),
    ("Hiszpania",         "ES", "EUR", "T2", ""),
    ("Japonia",           "JP", "JPY", "T2", ""),
    ("Korea Poludniowa",  "KR", "KRW", "T2", ""),
    ("Tajwan",            "TW", "TWD", "T2", ""),
    ("Polska",            "PL", "PLN", "T2", "TWOJA CENA BAZOWA (24,99 / 69,99)"),
    ("Czechy",            "CZ", "CZK", "T2", ""),
    ("Slowenia",          "SI", "EUR", "T2", ""),
    ("Estonia",           "EE", "EUR", "T2", ""),
    ("Litwa",             "LT", "EUR", "T2", ""),
    ("Lotwa",             "LV", "EUR", "T2", ""),
    ("Slowacja",          "SK", "EUR", "T2", ""),
    ("Portugalia",        "PT", "EUR", "T2", ""),
    ("Grecja",            "GR", "EUR", "T2", ""),
    ("Cypr",              "CY", "EUR", "T2", ""),
    ("Malta",             "MT", "EUR", "T2", ""),
    ("Chorwacja",         "HR", "EUR", "T2", ""),
    # ---- T3 Sredni-wyzszy ----
    ("Wegry",             "HU", "HUF", "T3", ""),
    ("Rumunia",           "RO", "RON", "T3", ""),
    ("Bulgaria",          "BG", "BGN", "T3", ""),
    ("Chile",             "CL", "CLP", "T3", ""),
    ("Chiny",             "CN", "CNY", "T3", "App Store CN: punkty cenowe calkowite"),
    ("Meksyk",            "MX", "MXN", "T3", ""),
    ("Malezja",           "MY", "MYR", "T3", ""),
    # ---- T4 Sredni-nizszy ----
    ("Brazylia",          "BR", "BRL", "T4", ""),
    ("RPA",               "ZA", "ZAR", "T4", ""),
    ("Tajlandia",         "TH", "THB", "T4", ""),
    ("Kolumbia",          "CO", "COP", "T4", ""),
    ("Peru",              "PE", "PEN", "T4", ""),
    ("Ukraina",           "UA", "UAH", "T4", ""),
    # ---- T5 Niski (poziom Indii) ----
    ("Indie",             "IN", "INR", "T5", ""),
    ("Indonezja",         "ID", "IDR", "T5", ""),
    ("Filipiny",          "PH", "PHP", "T5", ""),
    ("Wietnam",           "VN", "VND", "T5", ""),
    ("Nigeria",           "NG", "NGN", "T5", "Waluta zmienna - przegladaj kwartalnie"),
    ("Pakistan",          "PK", "PKR", "T5", ""),
    ("Egipt",             "EG", "EGP", "T5", ""),
    ("Turcja",            "TR", "TRY", "T5", "Waluta zmienna - przegladaj kwartalnie"),
    ("Bangladesz",        "BD", "BDT", "T5", ""),
    ("Kenia",             "KE", "KES", "T5", ""),
    ("Maroko",            "MA", "MAD", "T5", ""),
    ("Algieria",          "DZ", "DZD", "T5", ""),
]

# ---------------------------------------------------------------------------
# 4. ZAOKRAGLANIE "CHARM" (koncowki .99 / ...9)
# ---------------------------------------------------------------------------
DEC_LADDER = [0.99,1.49,1.99,2.49,2.99,3.49,3.99,4.49,4.99,5.99,6.99,7.99,8.99,
              9.99,10.99,11.99,12.99,13.99,14.99,15.99,16.99,17.99,18.99,19.99,
              20.99,21.99,22.99,23.99,24.99,26.99,27.99,29.99,32.99,34.99,37.99,
              39.99,44.99,49.99,54.99,59.99,64.99,69.99,74.99,79.99,89.99,99.99,
              109.99,119.99,129.99,149.99,169.99,199.99,249.99,299.99,349.99,399.99]

INT_LADDER = [9,19,29,39,49,59,69,79,89,99,
              119,129,139,149,159,169,179,189,199,
              229,249,269,279,299,329,349,379,399,
              429,449,479,499,549,599,649,699,749,799,849,899,949,999,
              1090,1190,1290,1390,1490,1590,1690,1790,1890,1990,
              2290,2490,2690,2990,3290,3490,3990,4290,4490,4990,
              5490,5990,6490,6990,7490,7990,8490,8990,9490,9900,9990,
              10900,11900,12900,13900,14900,16900,18900,19900,
              22900,24900,26900,29900,32900,34900,39900,44900,49000,
              54000,59000,64000,69000,74000,79000,84000,89000,94000,99000,
              119000,129000,149000,169000,199000,229000,249000,299000,349000,
              399000,449000,499000,590000,690000,790000,890000,990000]

KWD_LADDER = [round(n + f, 3) for n in range(0, 40) for f in (0.490, 0.990)]

def nearest(raw, ladder):
    return min(ladder, key=lambda c: abs(math.log(c) - math.log(raw)))

def charm(usd, cur):
    fx, dec = CUR[cur]
    raw = usd * fx
    if cur == "KWD":
        return nearest(raw, KWD_LADDER)
    if dec == 0:
        return float(nearest(raw, INT_LADDER))
    return nearest(raw, DEC_LADDER)

def price_for(cur, tier):
    m = charm(TIERS[tier]["m"], cur)
    l = charm(TIERS[tier]["l"], cur)
    return m, l

# Polska = dokladnie Twoje ustawione ceny (override).
PL_OVERRIDE = {"PLN": (24.99, 69.99)}

# ---------------------------------------------------------------------------
# 5. STYLE
# ---------------------------------------------------------------------------
FONT = "Arial"
C_HEAD   = PatternFill("solid", fgColor="1F2937")   # granatowa szarosc
C_TITLE  = PatternFill("solid", fgColor="111827")
TIER_FILL = {
    "T1": PatternFill("solid", fgColor="E8F0FE"),
    "T2": PatternFill("solid", fgColor="EAF7EE"),
    "T3": PatternFill("solid", fgColor="FEF7E0"),
    "T4": PatternFill("solid", fgColor="FDEEE3"),
    "T5": PatternFill("solid", fgColor="FCE8E6"),
}
PL_FILL = PatternFill("solid", fgColor="FFF3B0")     # zolty - Twoja baza
US_FILL = PatternFill("solid", fgColor="DDE7FB")
thin = Side(style="thin", color="D0D0D0")
BORDER = Border(left=thin, right=thin, top=thin, bottom=thin)

def numfmt(cur):
    _, dec = CUR[cur]
    if dec == 0:
        return "#,##0"
    if dec == 3:
        return "#,##0.000"
    return "#,##0.00"

HEADERS = ["Kraj / Region", "ISO", "Waluta", "Poziom PPP", "% ceny USA",
           "Miesieczna (lokalna)", "Lifetime (lokalna)", "≈ USD/mies (cel)", "Uwagi"]

def build_store_sheet(ws, store_name, intro_lines):
    ws.sheet_view.showGridLines = False
    widths = [22, 6, 8, 14, 11, 20, 20, 15, 40]
    for i, w in enumerate(widths, start=1):
        ws.column_dimensions[get_column_letter(i)].width = w

    # Tytul
    ws.merge_cells("A1:I1")
    t = ws["A1"]
    t.value = f"CENNIK REGIONALNY (PPP) - {store_name}   |   Debatly   |   {TODAY}"
    t.font = Font(name=FONT, size=14, bold=True, color="FFFFFF")
    t.fill = C_TITLE
    t.alignment = Alignment(horizontal="left", vertical="center", indent=1)
    ws.row_dimensions[1].height = 26

    # Intro
    r = 2
    for line in intro_lines:
        ws.merge_cells(start_row=r, start_column=1, end_row=r, end_column=9)
        c = ws.cell(row=r, column=1, value=line)
        c.font = Font(name=FONT, size=9, italic=line.startswith("•") is False and False or False)
        c.font = Font(name=FONT, size=9, color="374151")
        c.alignment = Alignment(horizontal="left", vertical="center", indent=1, wrap_text=False)
        r += 1
    r += 1

    # Naglowek tabeli
    head_row = r
    for j, h in enumerate(HEADERS, start=1):
        c = ws.cell(row=head_row, column=j, value=h)
        c.font = Font(name=FONT, size=10, bold=True, color="FFFFFF")
        c.fill = C_HEAD
        c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        c.border = BORDER
    ws.row_dimensions[head_row].height = 30

    # Wiersze
    row = head_row + 1
    for (name, iso, cur, tier, note) in COUNTRIES:
        if iso == "PL" and cur in PL_OVERRIDE:
            m, l = PL_OVERRIDE[cur]
        else:
            m, l = price_for(cur, tier)
        pct = TIERS[tier]["m"] / US_M
        vals = [name, iso, cur, f"{tier} · {TIERS[tier]['label']}", pct, m, l,
                TIERS[tier]["m"], note]
        for j, v in enumerate(vals, start=1):
            c = ws.cell(row=row, column=j, value=v)
            c.border = BORDER
            c.font = Font(name=FONT, size=10)
            if j == 1:
                c.alignment = Alignment(horizontal="left", vertical="center", indent=1)
            elif j == 9:
                c.alignment = Alignment(horizontal="left", vertical="center", indent=1)
                c.font = Font(name=FONT, size=8, color="6B7280")
            else:
                c.alignment = Alignment(horizontal="center", vertical="center")
            # formaty liczb
            if j == 5:
                c.number_format = "0%"
            elif j in (6, 7):
                c.number_format = numfmt(cur)
            elif j == 8:
                c.number_format = '"$"#,##0.00'
        # kolorowanie
        fill = TIER_FILL[tier]
        if iso == "PL":
            fill = PL_FILL
        elif iso == "US":
            fill = US_FILL
        for j in range(1, 10):
            if ws.cell(row=row, column=j).fill.fgColor.rgb in (None, "00000000"):
                ws.cell(row=row, column=j).fill = fill
            else:
                ws.cell(row=row, column=j).fill = fill
        row += 1

    ws.freeze_panes = ws.cell(row=head_row + 1, column=1)
    ws.auto_filter.ref = f"A{head_row}:I{row-1}"
    return row

# ---------------------------------------------------------------------------
# 6. BUDOWA WORKBOOKA
# ---------------------------------------------------------------------------
wb = Workbook()

# --- Zakladka: Instrukcja ---
wsi = wb.active
wsi.title = "Instrukcja"
wsi.sheet_view.showGridLines = False
wsi.column_dimensions["A"].width = 3
wsi.column_dimensions["B"].width = 110

INSTR = [
    ("H", "Cennik regionalny (PPP) - Debatly"),
    ("S", f"Wygenerowano: {TODAY}.  Waluta bazowa: PLN.  Produkty: subskrypcja miesieczna + Lifetime (jednorazowo)."),
    ("", ""),
    ("H2", "Po co ten plik"),
    ("P", "Apple i Google domyslnie przeliczaja Twoja cene bazowa TYLKO po kursie walutowym (FX), a nie po sile"),
    ("P", "nabywczej (PPP). Efekt: w Indiach, Nigerii czy Turcji cena wychodzi za wysoka i konwersja spada."),
    ("P", "Ten arkusz daje gotowe ceny per kraj, obnizone tam gdzie trzeba, a podniesione na bogatych rynkach."),
    ("", ""),
    ("H2", "Zalozony model"),
    ("P", "• Polska = punkt srodkowy (Twoje 24,99 / 69,99 zl zostaja bez zmian)."),
    ("P", "• USA = Tier 1 (100%). Bogate rynki (USA, AU, DACH, Skandynawia, Zatoka) placa wiecej."),
    ("P", "• Znizka PPP: UMIARKOWANA. Indie/Nigeria ~39% ceny USA."),
    ("P", "• Lifetime = ~2,8x ceny miesiecznej w kazdym kraju (spojny podpis 'mniej niz 3 miesiace')."),
    ("P", "• 5 poziomow PPP (T1-T5). Przypisanie kraju -> poziom w kolumnie 'Poziom PPP'."),
    ("", ""),
    ("H2", "Jak wpisac ceny - iOS (App Store Connect)"),
    ("P", "1. Monetization -> Subscriptions (miesieczna) oraz In-App Purchases (Lifetime jako Non-Consumable)."),
    ("P", "2. Ustaw cene BAZOWA dla USA wg zakladki 'iOS - App Store' (Tier 1)."),
    ("P", "3. Apple zaproponuje ceny dla 175 rynkow po FX. Nie zostawiaj tak - wejdz w 'All Prices and Currencies'."),
    ("P", "4. Dla krajow z listy USTAW RECZNIE cene z tabeli (wybierz najblizszy dostepny punkt cenowy Apple)."),
    ("P", "5. Apple ma stala siatke punktow cenowych - jesli nie ma dokladnie tej liczby, wybierz najblizsza."),
    ("", ""),
    ("H2", "Jak wpisac ceny - Android (Google Play Console)"),
    ("P", "1. Monetize -> Products -> Subscriptions (miesieczna) i In-app products (Lifetime)."),
    ("P", "2. Ustaw cene domyslna (USA/EUR), potem 'Set prices' / 'Manage prices' per kraj."),
    ("P", "3. Google pozwala na niemal dowolna cene lokalna - wpisz wartosci z zakladki 'Android - Google Play'."),
    ("P", "4. Dla produktow jednorazowych (Lifetime) mozesz uzyc importu CSV cen w Play Console."),
    ("P", "5. Wlacz 'Automatically convert' TYLKO dla krajow spoza tej listy (reszta swiata)."),
    ("", ""),
    ("H2", "Kraje spoza listy (reszta swiata)"),
    ("P", "Lista pokrywa ~65 najwazniejszych rynkow. Dla pozostalych: niech sklep przeliczy po FX z bazy USA,"),
    ("P", "a rynki wyraznie ubozsze (Afryka, Azja Pd.) potraktuj jak poziom T5."),
    ("", ""),
    ("H2", "Wazne zastrzezenia"),
    ("P", "• Kursy walut (zakladka 'Konfiguracja') to PRZYBLIZENIA ze stycznia 2026. Zweryfikuj przed wpisaniem."),
    ("P", "• Waluty zmienne (TRY, NGN, ARS) przegladaj kwartalnie - inflacja zjada cene realna."),
    ("P", "• To sa wartosci statyczne. Chcesz inna strategie/kursy? Popros o ponowne wygenerowanie."),
    ("P", "• Ceny to zaokraglenia 'charm' (.99 / ...9). W sklepie wybierz najblizszy dozwolony punkt cenowy."),
]
rr = 2
for kind, text in INSTR:
    c = wsi.cell(row=rr, column=2, value=text)
    if kind == "H":
        c.font = Font(name=FONT, size=16, bold=True, color="111827")
        wsi.row_dimensions[rr].height = 24
    elif kind == "S":
        c.font = Font(name=FONT, size=10, italic=True, color="6B7280")
    elif kind == "H2":
        c.font = Font(name=FONT, size=12, bold=True, color="1F4E79")
        wsi.row_dimensions[rr].height = 20
    else:
        c.font = Font(name=FONT, size=10, color="222222")
    c.alignment = Alignment(horizontal="left", vertical="center", wrap_text=False)
    rr += 1

# --- Zakladka: iOS ---
ws_ios = wb.create_sheet("iOS - App Store")
build_store_sheet(
    ws_ios, "iOS / App Store",
    [
        "Ustaw cene bazowa dla USA, potem NADPISZ recznie ceny krajow z listy (Apple domyslnie liczy tylko po kursie FX).",
        "Kolumny 'Miesieczna' i 'Lifetime' = cena w walucie lokalnej. Wybierz najblizszy dostepny punkt cenowy Apple.",
        "Zolty = Twoja cena bazowa (Polska).  Niebieski = USA (baza auto-przeliczenia).",
    ],
)

# --- Zakladka: Android ---
ws_and = wb.create_sheet("Android - Google Play")
build_store_sheet(
    ws_and, "Android / Google Play",
    [
        "Ustaw cene domyslna, potem wpisz ceny lokalne per kraj (Google pozwala na niemal dowolna cene).",
        "Kolumny 'Miesieczna' i 'Lifetime' = cena w walucie lokalnej. Dla Lifetime mozesz uzyc importu CSV.",
        "Zolty = Twoja cena bazowa (Polska).  Niebieski = USA (baza auto-przeliczenia).",
    ],
)

# --- Zakladka: Konfiguracja (referencja: kotwice + kursy) ---
wsc = wb.create_sheet("Konfiguracja")
wsc.sheet_view.showGridLines = False
wsc.column_dimensions["A"].width = 3
for col, w in zip("BCDEFG", [16, 16, 14, 14, 14, 14]):
    wsc.column_dimensions[col].width = w

wsc.merge_cells("B2:G2")
h = wsc["B2"]; h.value = "Konfiguracja modelu (wartosci referencyjne, statyczne)"
h.font = Font(name=FONT, size=14, bold=True, color="FFFFFF"); h.fill = C_TITLE
h.alignment = Alignment(horizontal="left", vertical="center", indent=1)
wsc.row_dimensions[2].height = 24

# Tabela kotwic
wsc.cell(row=4, column=2, value="Kotwice cenowe (USD) per poziom PPP").font = Font(name=FONT, size=12, bold=True, color="1F4E79")
kh = ["Poziom", "Nazwa", "Mies. (USD)", "Lifetime (USD)", "% ceny USA"]
for j, t in enumerate(kh, start=2):
    c = wsc.cell(row=5, column=j, value=t)
    c.font = Font(name=FONT, size=10, bold=True, color="FFFFFF"); c.fill = C_HEAD
    c.alignment = Alignment(horizontal="center"); c.border = BORDER
rr = 6
for tk, tv in TIERS.items():
    vals = [tk, tv["label"], tv["m"], tv["l"], tv["m"]/US_M]
    for j, v in enumerate(vals, start=2):
        c = wsc.cell(row=rr, column=j, value=v)
        c.border = BORDER; c.font = Font(name=FONT, size=10)
        c.alignment = Alignment(horizontal="center")
        c.fill = TIER_FILL[tk]
        if j in (4, 5):
            c.number_format = '"$"#,##0.00'
        if j == 6:
            c.number_format = "0%"
    wsc.cell(row=rr, column=6).number_format = "0%"
    rr += 1

# Tabela kursow
rr += 1
wsc.cell(row=rr, column=2, value="Kursy walut uzyte (za 1 USD, orientacyjne ~sty 2026)").font = Font(name=FONT, size=12, bold=True, color="1F4E79")
rr += 1
fh = ["Waluta", "Kurs / 1 USD", "Miejsca dz."]
for j, t in enumerate(fh, start=2):
    c = wsc.cell(row=rr, column=j, value=t)
    c.font = Font(name=FONT, size=10, bold=True, color="FFFFFF"); c.fill = C_HEAD
    c.alignment = Alignment(horizontal="center"); c.border = BORDER
rr += 1
for code in sorted(CUR):
    fx, dec = CUR[code]
    for j, v in enumerate([code, fx, dec], start=2):
        c = wsc.cell(row=rr, column=j, value=v)
        c.border = BORDER; c.font = Font(name=FONT, size=9)
        c.alignment = Alignment(horizontal="center")
        if j == 3:
            c.number_format = "#,##0.####"
    rr += 1

# --- zapis ---
import os
out_dir = r"F:\ProjektyAKNSoftware\questionapp\exports"
os.makedirs(out_dir, exist_ok=True)
out = os.path.join(out_dir, f"cennik_regionalny_{TODAY}.xlsx")
wb.save(out)
print("Zapisano:", out)

# szybki podglad kluczowych rynkow
print("\n--- Podglad (miesieczna / lifetime, lokalnie) ---")
for (name, iso, cur, tier, note) in COUNTRIES:
    if iso in ("US","PL","GB","DE","AU","JP","IN","BR","TR","NG","ID","MX","SA","KW"):
        if iso == "PL":
            m,l = PL_OVERRIDE[cur]
        else:
            m,l = price_for(cur,tier)
        print(f"{name:20s} {iso}  {cur}  {tier}  mies={m:>10}  life={l:>10}")
