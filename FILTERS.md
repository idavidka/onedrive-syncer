# rclone Filter Files

## Összefoglalás

Az OneDrive-on 4 nagy mappacsoportot kezelünk szeparáltan, mert ezek sok GB-ot tesznek ki.
A filterek meghatározzák, hogy az adott rclone futás mit szinkronizáljon.

A script mindig `rclone copy` (Safe) vagy `rclone sync` (Mirror) módban fut.
A `rclone copy` csak letölt, nem töröl. A `rclone sync` tükröz — de a filter által **kizárt mappákat nem érinti**.

---

## filter-small.txt

**Célja:** Mindent szinkronizál, kivéve a 4 nagy mappát.

Kizárja:
- `/Képek/**`
- `/Képek - régi/**`
- `/Dokumentumok/Családfa/Dokumentumok/Anyakönyvek/**`
- `/Dokumentumok/Családfa/Dokumentumok/Anyakönyvek új/**`

Hasznos ha: a mindennapi szinkronizáláshoz (dokumentumok, egyéb fájlok), a nagy képek és anyakönyvek nélkül.

---

## filter-kepek.txt

**Célja:** Szelektív szinkronizálás a `/Képek` mappán belül — almappánként engedélyezhető.

- Alapból **minden almappa ki van zárva** (`-`)
- Egy almappa engedélyezéséhez a két `-` sort kell `+`-ra cserélni indítás előtt
- Így csak az engedélyezett almappák töltődnek le

Hasznos ha: csak bizonyos képalbumokat akarsz letölteni lépésről lépésre.

---

## filter-kepek-regi.txt

**Célja:** Ugyanaz mint `filter-kepek.txt`, de a `/Képek - régi` mappára.

---

## filter-anyakonyvek.txt

**Célja:** Szelektív szinkronizálás a `/Dokumentumok/Családfa/Dokumentumok/Anyakönyvek` mappán belül.

- Alapból **minden almappa ki van zárva** (`-`)
- Egy almappa engedélyezéséhez a két `-` sort kell `+`-ra cserélni indítás előtt

Hasznos ha: egy-egy helység anyakönyveit akarod letölteni.

---

## filter-anyakonyvek-uj.txt

**Célja:** Ugyanaz mint `filter-anyakonyvek.txt`, de az `Anyakönyvek új` mappára.

---

## filter-kepek-all.txt

**Célja:** A teljes `/Képek` mappát szinkronizálja — minden almappát egyszerre.

Hasznos ha: az egész Képek mappát le akarod tölteni egy menetben.

---

## filter-kepek-regi-all.txt

**Célja:** A teljes `/Képek - régi` mappát szinkronizálja.

---

## filter-anyakonyvek-all.txt

**Célja:** A teljes `Anyakönyvek` mappát szinkronizálja — minden almappát egyszerre.

---

## filter-anyakonyvek-uj-all.txt

**Célja:** A teljes `Anyakönyvek új` mappát szinkronizálja.

---

## Filter nélkül (No filter)

Az egész OneDrive-ot szinkronizálja. A 4 nagy mappa is belekerül.
Csak akkor érdemes, ha valóban mindent akarod — nagyon lassú a listing fázis.

---

## Technikai megjegyzések

- Minden filter kizárja a `/Personal Vault/**` mappát (OneDrive titkosított tároló)
- A `+ */` traversal helyett explicit útvonal-lépések vannak (`+ /Dokumentumok/`, stb.) — ez gyorsabb, mert rclone nem jár be felesleges mappákat
- A fájlok NFC Unicode normalizálással vannak írva (macOS NFD vs. OneDrive NFC kompatibilitás)
- A per-almappa filterek (`filter-kepek.txt`, `filter-anyakonyvek.txt` stb.) láblécében `+ /RootMappa/*` engedélyezi a root szintű fájlokat, ha vannak
