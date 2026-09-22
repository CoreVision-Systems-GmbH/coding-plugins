# Stack-Overlay <Name> — <Framework/Version>

<!-- Vorlage für einen neuen Stack. Ein Stack besteht aus zwei Teilen:

     1. Dieses Overlay: kopieren nach stacks/<name>.md und ausfüllen. Regel: kein Satz, der
        im Kern schon steht; kein Framework-Lehrbuch — nur Firmenentscheidungen. ≤ 120 Zeilen.
     2. Das Register für /projekt-neu: templates/_vorlage/ nach templates/<name>/ kopieren.
        Darin
          stack.conf    LABEL, DESCRIPTION, REQUIRES, CONTAINERIZED, MARKER (kommentiert)
          befehle.md    der Befehlsblock, der in die CLAUDE.md des Projekts wandert
          scaffold.sh   optional: Installer (PHASE=geruest) und Einrichtung (PHASE=einrichten)
          dateien/      alles, was ins neue Projekt kopiert wird (Platzhalter {{NAME}} …)

     Erkennung: Erkennt der Hook den Stack an einer Markerdatei des Frameworks, die
     Erkennungszeile in hooks/standard-context.sh ergänzen und einen Fall in
     hooks/test-standard-context.sh. Gibt es keine, MARKER=1 in stack.conf setzen — dann
     schreibt der Bootstrap `.coding-standard` mit der Zeile `stack: <name>` ins Projekt.

     Dazu ein Fall in scripts/test-projekt-neu.sh und, wenn der Stack von Hand nachladbar
     sein soll, ein dünner Skill skills/<name>/SKILL.md nach dem Muster von skills/fastapi. -->

Ergänzt den Kern für <Art der Projekte>. Hier stehen Firmenentscheidungen; Idiome kommen aus <offizielle Quelle>.

## 1. Zuständigkeiten & Architektur
- Welche Schicht ist wofür autoritativ? Welche Ablage (Ordner) gilt, und was hat Vorrang, wenn das Repo abweicht?
- Welche Oberfläche/Adapter für welchen Nutzerkreis?
- Was wird vor dem Code je Funktion festgehalten (Entscheidungsformel)?

## 2. Grenzen (nicht verhandelbar)
- Was darf nie wo liegen (Geschäftsregeln, Autorisierung, Secrets)?
- Welche Eingaben sind nie autoritativ?

## 3. Werkzeugkette
- Wie werden die Projektbefehle ermittelt (nie erfinden)? Was ist der Standardsatz für neue Projekte (Formatter, Linter, Statik, Tests, Audit)?
- Reihenfolge in der CI. Was ist in der CI verboten (z. B. Befehle, die migrieren)?
- Eigenheiten der Entwicklungsumgebung (Windows, Toolchain-Pfade).

## 4. Betriebsvertrag
1. **Runtime:** Basis-Image, Prozessmodell, Port, Rollen; TLS beim Edge-Caddy, kein veröffentlichter Port.
2. **Konfiguration:** ENV-Schema, Secret-Ablage (KeePassXC), Instanz-Pin.
3. **Health:** Endpunkt und Compose-Healthcheck.
4. **Logs:** stdout, Struktur, keine PII.
5. **Version im Produkt:** Build-Arg → sichtbar wo?
6. **Lieferung:** `release.yml` → GHCR → `deploy/update.sh <tag>` (auf Prod über `rollout`); Dev-Instanz über `deploy/dev.sh` und `compose.dev.yaml`; Migrationsregel.
7. **Daten:** Volumes, Backup-Verfahren.
8. **Qualitätsgates:** numerisch, prüfbar.

## 5. Fallen (stack-typisch)
- Nur, was ein Linter nicht findet und das Framework nicht dokumentiert. Projekt-Fallen gehören in die `CLAUDE.md` des Repos.
