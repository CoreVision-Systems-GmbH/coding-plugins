# KI-Modelle — <Projekt>

Pflicht, sobald das Produkt selbst eine KI-Funktion hat (Kern, „Arbeiten mit KI“): Hier steht,
welches Modell was tut, und die Funktion ist in der Oberfläche als KI gekennzeichnet — das ist
Firmenregel. Gesetzlich verlangt die KI-Verordnung (Art. 50) die Kennzeichnung in bestimmten
Fällen: direkte Interaktion mit Menschen (Abs. 1), erzeugte Inhalte — als Anbieter zusätzlich
maschinenlesbar markiert (Abs. 2) —, Emotionserkennung und biometrische Kategorisierung (Abs. 3),
Deepfakes und erzeugte Texte zu Themen von öffentlichem Interesse (Abs. 4).
`scripts/konfig-pruefen.sh` meldet eine ausgelieferte KI-Bibliothek ohne diese Datei. Vorlage aus
dem Standard: nach `docs/ki-modelle.md` kopieren und ausfüllen.

## Modelle

| Funktion | Modell (Anbieter, Kennung, Fassung) | Wo es läuft (Cloud mit Region / lokal) | Unsere Rolle (Anbieter / Betreiber) | Risikoklasse | Welche Daten hingehen | Kennzeichnung (Oberfläche / maschinenlesbar) |
|---|---|---|---|---|---|---|
| | | | | | | |

- **Rolle:** Anbieter ist, wer ein KI-System entwickelt oder entwickeln lässt und es unter eigenem
  Namen in Verkehr bringt oder in Betrieb nimmt (Art. 3 Nr. 3); wer ein fremdes Modell per API in
  ein eigenes Produkt einbaut, ist Anbieter dieses KI-Systems. Betreiber ist, wer ein KI-System in
  eigener Verantwortung verwendet (Art. 3 Nr. 4).
- **Risikoklasse:** verboten / hoch / mit Transparenzpflicht / minimal — mit einem Satz
  Begründung.

## Daten

Gehen personenbezogene Daten an einen KI-Dienst, braucht das eine Rechtsgrundlage und einen
Vertrag zur Auftragsverarbeitung mit dem Anbieter; der Dienst steht dann auch in
`docs/datenschutz.md` unter „Empfänger“. Geheimnisse gehen nie an einen KI-Dienst.

## Änderungen

| Datum | Was | Warum |
|---|---|---|
| | | |
