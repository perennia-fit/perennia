# Perennia Platform Exercise Library Data License

SPDX-License-Identifier: CC-BY-SA-4.0

This file applies to `platform_exercises.json`, the bundled Platform Exercise
Library data asset. The application source code in the rest of the repository is
licensed separately by the repository root `LICENSE`.

The bundled data asset is offered under the Creative Commons Attribution-ShareAlike
4.0 International license: https://creativecommons.org/licenses/by-sa/4.0/

## Sources And Changes

- wger exercise fixtures: https://github.com/wger-project/wger
- wger commit: ea7844731f7e3fe5865c327c1f93f5f4a76dde75
- Workout.cool exercise API and repository: https://github.com/Snouzy/workout-cool
- Workout.cool API endpoint used by the generator: https://workout.cool/api/exercises/all

Changes were made by Perennia:

- English exercise names were cleaned for app display.
- wger categories were mapped into Perennia Categories.
- Perennia Exercise Type input dimensions were inferred.
- Structured equipment identifiers were normalized into Perennia Equipment.
- Workout.cool English names and structured type/muscle/equipment attributes were
  compared with the wger-derived seed to enrich matched records and add missing
  exercise rows.
- Images, videos, thumbnails, generated descriptions, and UI assets were not copied.

## Source License Posture

wger fixture records carry per-record license and author metadata. The generated
JSON retains that metadata in each wger-derived exercise's `source_attribution`
object. Because the data pack adapts CC-BY-SA records, the complete bundled data
asset is distributed under CC-BY-SA 4.0.

Workout.cool's application source is MIT licensed, but the upstream exercise-data
provenance is not declared. Perennia imports only factual English names and
structured attributes from Workout.cool, and records that source boundary in the
generated JSON. Workout.cool contribution counts for this generation:

- 1044 source records read.
- 48 source records matched existing rows.
- 25 existing rows enriched.
- 995 missing exercise rows added.

## wger Author Attribution Buckets

The following names are copied from wger's `license_author` fixture fields for
records that contributed to this generated seed. Names are grouped by the source
license id/title reported by wger.

### CC-BY-SA 3

Distinct source author count: 37.

- andikeller
- aszc
- bizyguy
- cgoob883
- Dexter
- djblitzd
- drthurlow
- flori
- foguinho.peruca
- GiglioRosso
- GrosseHund
- http://www.bodybuilding.com/
- http://www.carinatum.com/
- http://www.exrx.net/WeightExercises/Brachialis/DBC
- J120290,cerin
- klabautermann
- kwrindy
- lakerbeezel
- lauroernesto
- MaddieBeasley
- Mahoney
- Manu, wikipedia
- Marius
- mbozi1
- minifigmaster125
- Nallitnas
- OGhTebfCxhexZXuf35mUxV9C--A
- oliser67
- powerade69
- robhoyt
- sistab2
- ThisGirl0819
- trzr23
- tuckerm
- tuninx
- wger.de
- YYCfit

### CC-BY-SA 4

Distinct source author count: 179.

- 2dPREtEZP221u68Akf0JImv5L48
- 3leh
- 54str
- 6LXBO
- aahuja
- abeworld
- aboksz
- abuono
- admin
- AlucardEvil40
- amaesc
- Anastasious
- anon1337
- anto.kreegyr
- Antsy6277
- apeschel
- arson
- ataraxie67
- baldurmen
- barry
- bbayuwega
- beagle
- BeLikeWater
- benjamin.yildiz@proton.me
- BePieToday
- bl0sh
- bobbyprince89
- Boertie
- Bret Contreras
- Brigade7938
- brucem
- burenl
- cal.zabel
- captive0592
- carlos3c
- Cerin
- clafal
- cleen
- colundrum
- cozyGalvinism
- CptnFatbeard
- Croak6728
- cshep442
- cybro
- cynomops
- daiben
- damnlost
- daniel.escada
- Davidgj32
- Deflation
- delta@romeo
- deusinvictus
- DiscoCop
- donaddon
- dookie1481
- Dulive
- enros7500
- Epiphany8424
- er0355
- erikocobra
- eriktrinkle
- eufvksruh
- Expenses7000
- ExRx
- fabrice
- FEFFO
- Fittness69
- flanny
- florian.bussmann
- FoyrhzMarin789
- Franpol
- Gavru
- geraldbaeck
- Happy
- hektkaso
- hpmbala@gmail.com
- http://www.realsimple.com/health/fitness-exercise/
- hurr99
- Iko
- Imobard
- Insight
- intelman
- ISSACS
- JackSparrow
- James Mackay
- jayninja
- Jhonatan
- Joculari
- JohnPreston
- karly
- kmcalderwood
- Konsumopfer
- koreyhinton
- krisbbb
- LEBRERO
- lh1701
- lhegedus
- lion
- lxmx
- Lynn_McIntyre
- m4k3r
- M9
- magdy
- manuher89
- marcelbader
- Mariano_O
- matpn
- McMarcel13
- meldun
- Metin
- mhe
- mike6426
- Mikko Ruohola
- MisterPinnacle
- Moffi
- mountain.potato
- MrAlfaRobot
- MrSteele
- MU5H
- Nash
- nate303303
- nishant0712
- notdefine
- novadani
- oboema
- painDpice
- Papazit
- PaukOne
- Paul@Chemistry
- pera_perkan
- Pete
- philip
- phpi
- polloperro
- prevail90
- pwiltrout
- ricardodavidrd
- RiccaBaro
- ricwheatley
- Robertcoop
- roneydya
- Rottekongen
- schweezer
- schwolfar
- sebk
- Settebello
- sevae
- Shiladree
- shushu
- Skadi
- sophialj
- spacetowaste
- sTiKyt
- student1234
- taylorbarbell
- tdprice12
- technofer
- tekknokrat@gmx.de
- tenebrizz
- teus_ergaster
- Tierrasverdes
- tinman
- Torsten Linnecke
- treder
- tregga
- Trix
- utkb
- Vazco
- vdrb
- Vilhelmo
- vince63
- vkylamba
- wakanda90
- wget@pytt.io
- Whythebigpaws
- WiNNiE
- workout@rooven.anonaddy.me
- Yderkone
- zdelko

### CC0

Distinct source author count: 7.

- Behrooz
- BeLikeWater
- BFad07
- Blablabla
- fletchgraham
- jigglychipmunk
- Mens Fitness
