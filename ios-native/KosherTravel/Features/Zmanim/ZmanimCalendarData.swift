// The Jewish calendar facts for the Zmanim card, copied unchanged from the website's src/lib/zmanim/calendarData.ts
// (generated there by scripts/zmanim/buildZmanimCalendar.mjs; diaspora, 2026-01-02 .. 2036-12-28).
// Each line: YYYYMMDD|flags|names. Flags: c = candle lighting before sunset, t = candle lighting after nightfall (from an
// existing flame), h = havdalah, y = Yom Tov, fb/fn = fast begins at dawn / at sunset, fe = fast ends.
import Foundation

enum ZmanimCalendarData {
    static let text = #"""
20260102|c|
20260103|h|Parshas Vayechi
20260109|c|
20260110|h|Parshas Shemos
20260116|c|
20260117|h|Parshas Vaera
20260119||Rosh Chodesh Sh'vat
20260123|c|
20260124|h|Parshas Bo
20260130|c|
20260131|h|Parshas Beshalach;Shabbos Shirah
20260202||Tu BiShvat
20260206|c|
20260207|h|Parshas Yisro
20260213|c|
20260214|h|Parshas Mishpatim;Shabbos Shekalim
20260217||Rosh Chodesh Adar
20260218||Rosh Chodesh Adar
20260220|c|
20260221|h|Parshas Terumah
20260227|c|
20260228|h|Parshas Tetzaveh;Shabbos Zachor
20260302|fb,fe|Ta'anis Esther
20260303||Purim
20260304||Shushan Purim
20260306|c|
20260307|h|Parshas Ki Sisa;Shabbos Parah
20260313|c|
20260314|h|Parshas Vayakhel-Pekudei;Shabbos HaChodesh
20260319||Rosh Chodesh Nisan
20260320|c|
20260321|h|Parshas Vayikra
20260327|c|
20260328|h|Parshas Tzav;Shabbos HaGadol
20260401|c,fb|Ta'anis Bechoros;Erev Pesach
20260402|t,y|Pesach I
20260403|c,y|Pesach II
20260404|h|Pesach III (Chol Hamoed)
20260405||Pesach IV (Chol Hamoed)
20260406||Pesach V (Chol Hamoed)
20260407|c|Pesach VI (Chol Hamoed)
20260408|t,y|Pesach VII
20260409|h,y|Pesach VIII
20260410|c|
20260411|h|Parshas Shmini
20260417|c|Rosh Chodesh Iyyar
20260418|h|Parshas Tazria-Metzora;Rosh Chodesh Iyyar
20260424|c|
20260425|h|Parshas Achrei Mos-Kedoshim
20260501|c|Pesach Sheni
20260502|h|Parshas Emor
20260505||Lag BaOmer
20260508|c|
20260509|h|Parshas Behar-Bechukosai
20260515|c|
20260516|h|Parshas Bamidbar
20260517||Rosh Chodesh Sivan
20260521|c|Erev Shavuos
20260522|c,y|Shavuos I
20260523|h,y|Shavuos II
20260529|c|
20260530|h|Parshas Nasso
20260605|c|
20260606|h|Parshas Beha'aloscha
20260612|c|
20260613|h|Parshas Sh'lach
20260615||Rosh Chodesh Tamuz
20260616||Rosh Chodesh Tamuz
20260619|c|
20260620|h|Parshas Korach
20260626|c|
20260627|h|Parshas Chukas-Balak
20260702|fb,fe|Tzom Tammuz
20260703|c|
20260704|h|Parshas Pinchas
20260710|c|
20260711|h|Parshas Matos-Masei
20260715||Rosh Chodesh Av
20260717|c|
20260718|h|Parshas Devarim;Shabbos Chazon
20260722|fn|Erev Tish'a B'Av
20260723|fe|Tish'a B'Av
20260724|c|
20260725|h|Parshas Vaeschanan;Shabbos Nachamu
20260729||Tu B'Av
20260731|c|
20260801|h|Parshas Eikev
20260807|c|
20260808|h|Parshas Re'eh
20260813||Rosh Chodesh Elul
20260814|c|Rosh Hashana LaBeheimos;Rosh Chodesh Elul
20260815|h|Parshas Shoftim
20260821|c|
20260822|h|Parshas Ki Seitzei
20260828|c|
20260829|h|Parshas Ki Savo
20260904|c|
20260905|h|Parshas Nitzavim-Vayeilech;Leil Selichos
20260911|c|Erev Rosh Hashana
20260912|t,y|Rosh Hashana 5787
20260913|h,y|Rosh Hashana II
20260914|fb,fe|Tzom Gedaliah
20260918|c|
20260919|h|Parshas Ha'azinu;Shabbos Shuvah
20260920|c|Erev Yom Kippur
20260921|h,y|Yom Kippur
20260925|c|Erev Sukkos
20260926|t,y|Sukkos I
20260927|h,y|Sukkos II
20260928||Sukkos III (Chol Hamoed)
20260929||Sukkos IV (Chol Hamoed)
20260930||Sukkos V (Chol Hamoed)
20261001||Sukkos VI (Chol Hamoed)
20261002|c|Sukkos VII (Hoshana Raba)
20261003|t,y|Shmini Atzeres
20261004|h,y|Simchas Torah
20261009|c|
20261010|h|Parshas Bereshis
20261011||Rosh Chodesh Cheshvan
20261012||Rosh Chodesh Cheshvan
20261016|c|
20261017|h|Parshas Noach
20261023|c|
20261024|h|Parshas Lech-Lecha
20261030|c|
20261031|h|Parshas Vayera
20261106|c|
20261107|h|Parshas Chayei Sara
20261110||Rosh Chodesh Kislev
20261111||Rosh Chodesh Kislev
20261113|c|
20261114|h|Parshas Toldos
20261120|c|
20261121|h|Parshas Vayetzei
20261127|c|
20261128|h|Parshas Vayishlach
20261204|c|Chanukah: 1 candle tonight
20261205|h|Parshas Vayeshev;Chanukah: 2 candles tonight
20261206||Chanukah: 3 candles tonight
20261207||Chanukah: 4 candles tonight
20261208||Chanukah: 5 candles tonight
20261209||Chanukah: 6 candles tonight
20261210||Rosh Chodesh Teves;Chanukah: 7 candles tonight
20261211|c|Rosh Chodesh Teves;Chanukah: 8 candles tonight
20261212|h|Parshas Miketz;Chanukah (8th day)
20261218|c|
20261219|h|Parshas Vayigash
20261220|fb,fe|Asara B'Teves
20261225|c|
20261226|h|Parshas Vayechi
20270101|c|
20270102|h|Parshas Shemos
20270108|c|
20270109|h|Parshas Vaera;Rosh Chodesh Sh'vat
20270115|c|
20270116|h|Parshas Bo
20270122|c|
20270123|h|Parshas Beshalach;Shabbos Shirah;Tu BiShvat
20270129|c|
20270130|h|Parshas Yisro
20270205|c|
20270206|h|Parshas Mishpatim
20270207||Rosh Chodesh Adar I
20270208||Rosh Chodesh Adar I
20270212|c|
20270213|h|Parshas Terumah
20270219|c|
20270220|h|Parshas Tetzaveh
20270221||Purim Koton
20270222||Shushan Purim Koton
20270226|c|
20270227|h|Parshas Ki Sisa
20270305|c|
20270306|h|Parshas Vayakhel;Shabbos Shekalim
20270309||Rosh Chodesh Adar II
20270310||Rosh Chodesh Adar II
20270312|c|
20270313|h|Parshas Pekudei
20270319|c|
20270320|h|Parshas Vayikra;Shabbos Zachor
20270322|fb,fe|Ta'anis Esther
20270323||Purim
20270324||Shushan Purim
20270326|c|
20270327|h|Parshas Tzav;Shabbos Parah
20270402|c|
20270403|h|Parshas Shmini;Shabbos HaChodesh
20270408||Rosh Chodesh Nisan
20270409|c|
20270410|h|Parshas Tazria
20270416|c|
20270417|h|Parshas Metzora;Shabbos HaGadol
20270421|c,fb|Ta'anis Bechoros;Erev Pesach
20270422|t,y|Pesach I
20270423|c,y|Pesach II
20270424|h|Pesach III (Chol Hamoed)
20270425||Pesach IV (Chol Hamoed)
20270426||Pesach V (Chol Hamoed)
20270427|c|Pesach VI (Chol Hamoed)
20270428|t,y|Pesach VII
20270429|h,y|Pesach VIII
20270430|c|
20270501|h|Parshas Achrei Mos
20270507|c|Rosh Chodesh Iyyar
20270508|h|Parshas Kedoshim;Rosh Chodesh Iyyar
20270514|c|
20270515|h|Parshas Emor
20270521|c|Pesach Sheni
20270522|h|Parshas Behar
20270525||Lag BaOmer
20270528|c|
20270529|h|Parshas Bechukosai
20270604|c|
20270605|h|Parshas Bamidbar
20270606||Rosh Chodesh Sivan
20270610|c|Erev Shavuos
20270611|c,y|Shavuos I
20270612|h,y|Shavuos II
20270618|c|
20270619|h|Parshas Nasso
20270625|c|
20270626|h|Parshas Beha'aloscha
20270702|c|
20270703|h|Parshas Sh'lach
20270705||Rosh Chodesh Tamuz
20270706||Rosh Chodesh Tamuz
20270709|c|
20270710|h|Parshas Korach
20270716|c|
20270717|h|Parshas Chukas-Balak
20270722|fb,fe|Tzom Tammuz
20270723|c|
20270724|h|Parshas Pinchas
20270730|c|
20270731|h|Parshas Matos-Masei
20270804||Rosh Chodesh Av
20270806|c|
20270807|h|Parshas Devarim;Shabbos Chazon
20270811|fn|Erev Tish'a B'Av
20270812|fe|Tish'a B'Av
20270813|c|
20270814|h|Parshas Vaeschanan;Shabbos Nachamu
20270818||Tu B'Av
20270820|c|
20270821|h|Parshas Eikev
20270827|c|
20270828|h|Parshas Re'eh
20270902||Rosh Chodesh Elul
20270903|c|Rosh Hashana LaBeheimos;Rosh Chodesh Elul
20270904|h|Parshas Shoftim
20270910|c|
20270911|h|Parshas Ki Seitzei
20270917|c|
20270918|h|Parshas Ki Savo
20270924|c|
20270925|h|Parshas Nitzavim-Vayeilech;Leil Selichos
20271001|c|Erev Rosh Hashana
20271002|t,y|Rosh Hashana 5788
20271003|h,y|Rosh Hashana II
20271004|fb,fe|Tzom Gedaliah
20271008|c|
20271009|h|Parshas Ha'azinu;Shabbos Shuvah
20271010|c|Erev Yom Kippur
20271011|h,y|Yom Kippur
20271015|c|Erev Sukkos
20271016|t,y|Sukkos I
20271017|h,y|Sukkos II
20271018||Sukkos III (Chol Hamoed)
20271019||Sukkos IV (Chol Hamoed)
20271020||Sukkos V (Chol Hamoed)
20271021||Sukkos VI (Chol Hamoed)
20271022|c|Sukkos VII (Hoshana Raba)
20271023|t,y|Shmini Atzeres
20271024|h,y|Simchas Torah
20271029|c|
20271030|h|Parshas Bereshis
20271031||Rosh Chodesh Cheshvan
20271101||Rosh Chodesh Cheshvan
20271105|c|
20271106|h|Parshas Noach
20271112|c|
20271113|h|Parshas Lech-Lecha
20271119|c|
20271120|h|Parshas Vayera
20271126|c|
20271127|h|Parshas Chayei Sara
20271130||Rosh Chodesh Kislev
20271201||Rosh Chodesh Kislev
20271203|c|
20271204|h|Parshas Toldos
20271210|c|
20271211|h|Parshas Vayetzei
20271217|c|
20271218|h|Parshas Vayishlach
20271224|c|Chanukah: 1 candle tonight
20271225|h|Parshas Vayeshev;Chanukah: 2 candles tonight
20271226||Chanukah: 3 candles tonight
20271227||Chanukah: 4 candles tonight
20271228||Chanukah: 5 candles tonight
20271229||Chanukah: 6 candles tonight
20271230||Rosh Chodesh Teves;Chanukah: 7 candles tonight
20271231|c|Rosh Chodesh Teves;Chanukah: 8 candles tonight
20280101|h|Parshas Miketz;Chanukah (8th day)
20280107|c|
20280108|h|Parshas Vayigash
20280109|fb,fe|Asara B'Teves
20280114|c|
20280115|h|Parshas Vayechi
20280121|c|
20280122|h|Parshas Shemos
20280128|c|
20280129|h|Parshas Vaera;Rosh Chodesh Sh'vat
20280204|c|
20280205|h|Parshas Bo
20280211|c|
20280212|h|Parshas Beshalach;Shabbos Shirah;Tu BiShvat
20280218|c|
20280219|h|Parshas Yisro
20280225|c|
20280226|h|Parshas Mishpatim;Shabbos Shekalim
20280227||Rosh Chodesh Adar
20280228||Rosh Chodesh Adar
20280303|c|
20280304|h|Parshas Terumah
20280309|fb,fe|Ta'anis Esther
20280310|c|
20280311|h|Parshas Tetzaveh;Shabbos Zachor
20280312||Purim
20280313||Shushan Purim
20280317|c|
20280318|h|Parshas Ki Sisa;Shabbos Parah
20280324|c|
20280325|h|Parshas Vayakhel-Pekudei;Shabbos HaChodesh
20280328||Rosh Chodesh Nisan
20280331|c|
20280401|h|Parshas Vayikra
20280407|c|
20280408|h|Parshas Tzav;Shabbos HaGadol
20280410|c,fb|Ta'anis Bechoros;Erev Pesach
20280411|t,y|Pesach I
20280412|h,y|Pesach II
20280413||Pesach III (Chol Hamoed)
20280414|c|Pesach IV (Chol Hamoed)
20280415|h|Pesach V (Chol Hamoed)
20280416|c|Pesach VI (Chol Hamoed)
20280417|t,y|Pesach VII
20280418|h,y|Pesach VIII
20280421|c|
20280422|h|Parshas Shmini
20280426||Rosh Chodesh Iyyar
20280427||Rosh Chodesh Iyyar
20280428|c|
20280429|h|Parshas Tazria-Metzora
20280505|c|
20280506|h|Parshas Achrei Mos-Kedoshim
20280510||Pesach Sheni
20280512|c|
20280513|h|Parshas Emor
20280514||Lag BaOmer
20280519|c|
20280520|h|Parshas Behar-Bechukosai
20280526|c|Rosh Chodesh Sivan
20280527|h|Parshas Bamidbar
20280530|c|Erev Shavuos
20280531|t,y|Shavuos I
20280601|h,y|Shavuos II
20280602|c|
20280603|h|Parshas Nasso
20280609|c|
20280610|h|Parshas Beha'aloscha
20280616|c|
20280617|h|Parshas Sh'lach
20280623|c|
20280624|h|Parshas Korach;Rosh Chodesh Tamuz
20280625||Rosh Chodesh Tamuz
20280630|c|
20280701|h|Parshas Chukas
20280707|c|
20280708|h|Parshas Balak
20280711|fb,fe|Tzom Tammuz
20280714|c|
20280715|h|Parshas Pinchas
20280721|c|
20280722|h|Parshas Matos-Masei
20280724||Rosh Chodesh Av
20280728|c|
20280729|h|Parshas Devarim;Shabbos Chazon
20280731|fn|Erev Tish'a B'Av
20280801|fe|Tish'a B'Av
20280804|c|
20280805|h|Parshas Vaeschanan;Shabbos Nachamu
20280807||Tu B'Av
20280811|c|
20280812|h|Parshas Eikev
20280818|c|
20280819|h|Parshas Re'eh
20280822||Rosh Chodesh Elul
20280823||Rosh Hashana LaBeheimos;Rosh Chodesh Elul
20280825|c|
20280826|h|Parshas Shoftim
20280901|c|
20280902|h|Parshas Ki Seitzei
20280908|c|
20280909|h|Parshas Ki Savo
20280915|c|
20280916|h|Parshas Nitzavim-Vayeilech;Leil Selichos
20280920|c|Erev Rosh Hashana
20280921|t,y|Rosh Hashana 5789
20280922|c,y|Rosh Hashana II
20280923|h|Parshas Ha'azinu;Shabbos Shuvah
20280924|fb,fe|Tzom Gedaliah
20280929|c|Erev Yom Kippur
20280930|h,y|Yom Kippur
20281004|c|Erev Sukkos
20281005|t,y|Sukkos I
20281006|c,y|Sukkos II
20281007|h|Sukkos III (Chol Hamoed)
20281008||Sukkos IV (Chol Hamoed)
20281009||Sukkos V (Chol Hamoed)
20281010||Sukkos VI (Chol Hamoed)
20281011|c|Sukkos VII (Hoshana Raba)
20281012|t,y|Shmini Atzeres
20281013|c,y|Simchas Torah
20281014|h|Parshas Bereshis
20281020|c|Rosh Chodesh Cheshvan
20281021|h|Parshas Noach;Rosh Chodesh Cheshvan
20281027|c|
20281028|h|Parshas Lech-Lecha
20281103|c|
20281104|h|Parshas Vayera
20281110|c|
20281111|h|Parshas Chayei Sara
20281117|c|
20281118|h|Parshas Toldos
20281119||Rosh Chodesh Kislev
20281124|c|
20281125|h|Parshas Vayetzei
20281201|c|
20281202|h|Parshas Vayishlach
20281208|c|
20281209|h|Parshas Vayeshev
20281212||Chanukah: 1 candle tonight
20281213||Chanukah: 2 candles tonight
20281214||Chanukah: 3 candles tonight
20281215|c|Chanukah: 4 candles tonight
20281216|h|Parshas Miketz;Chanukah: 5 candles tonight
20281217||Chanukah: 6 candles tonight
20281218||Rosh Chodesh Teves;Chanukah: 7 candles tonight
20281219||Rosh Chodesh Teves;Chanukah: 8 candles tonight
20281220||Chanukah (8th day)
20281222|c|
20281223|h|Parshas Vayigash
20281228|fb,fe|Asara B'Teves
20281229|c|
20281230|h|Parshas Vayechi
20290105|c|
20290106|h|Parshas Shemos
20290112|c|
20290113|h|Parshas Vaera
20290117||Rosh Chodesh Sh'vat
20290119|c|
20290120|h|Parshas Bo
20290126|c|
20290127|h|Parshas Beshalach;Shabbos Shirah
20290131||Tu BiShvat
20290202|c|
20290203|h|Parshas Yisro
20290209|c|
20290210|h|Parshas Mishpatim;Shabbos Shekalim
20290215||Rosh Chodesh Adar
20290216|c|Rosh Chodesh Adar
20290217|h|Parshas Terumah
20290223|c|
20290224|h|Parshas Tetzaveh;Shabbos Zachor
20290228|fb,fe|Ta'anis Esther
20290301||Purim
20290302|c|Shushan Purim
20290303|h|Parshas Ki Sisa
20290309|c|
20290310|h|Parshas Vayakhel-Pekudei;Shabbos Parah
20290316|c|
20290317|h|Parshas Vayikra;Shabbos HaChodesh;Rosh Chodesh Nisan
20290323|c|
20290324|h|Parshas Tzav;Shabbos HaGadol
20290330|c,fb|Ta'anis Bechoros;Erev Pesach
20290331|t,y|Pesach I
20290401|h,y|Pesach II
20290402||Pesach III (Chol Hamoed)
20290403||Pesach IV (Chol Hamoed)
20290404||Pesach V (Chol Hamoed)
20290405|c|Pesach VI (Chol Hamoed)
20290406|c,y|Pesach VII
20290407|h,y|Pesach VIII
20290413|c|
20290414|h|Parshas Shmini
20290415||Rosh Chodesh Iyyar
20290416||Rosh Chodesh Iyyar
20290420|c|
20290421|h|Parshas Tazria-Metzora
20290427|c|
20290428|h|Parshas Achrei Mos-Kedoshim
20290429||Pesach Sheni
20290503||Lag BaOmer
20290504|c|
20290505|h|Parshas Emor
20290511|c|
20290512|h|Parshas Behar-Bechukosai
20290515||Rosh Chodesh Sivan
20290518|c|
20290519|t|Parshas Bamidbar;Erev Shavuos
20290520|t,y|Shavuos I
20290521|h,y|Shavuos II
20290525|c|
20290526|h|Parshas Nasso
20290601|c|
20290602|h|Parshas Beha'aloscha
20290608|c|
20290609|h|Parshas Sh'lach
20290613||Rosh Chodesh Tamuz
20290614||Rosh Chodesh Tamuz
20290615|c|
20290616|h|Parshas Korach
20290622|c|
20290623|h|Parshas Chukas
20290629|c|
20290630|h|Parshas Balak
20290701|fb,fe|Tzom Tammuz
20290706|c|
20290707|h|Parshas Pinchas
20290713|c|Rosh Chodesh Av
20290714|h|Parshas Matos-Masei
20290720|c|
20290721|fn,h|Parshas Devarim;Shabbos Chazon;Erev Tish'a B'Av
20290722|fe|Tish'a B'Av (observed)
20290727|c|Tu B'Av
20290728|h|Parshas Vaeschanan;Shabbos Nachamu
20290803|c|
20290804|h|Parshas Eikev
20290810|c|
20290811|h|Parshas Re'eh;Rosh Chodesh Elul
20290812||Rosh Hashana LaBeheimos;Rosh Chodesh Elul
20290817|c|
20290818|h|Parshas Shoftim
20290824|c|
20290825|h|Parshas Ki Seitzei
20290831|c|
20290901|h|Parshas Ki Savo;Leil Selichos
20290907|c|
20290908|h|Parshas Nitzavim
20290909|c|Erev Rosh Hashana
20290910|t,y|Rosh Hashana 5790
20290911|h,y|Rosh Hashana II
20290912|fb,fe|Tzom Gedaliah
20290914|c|
20290915|h|Parshas Vayeilech;Shabbos Shuvah
20290918|c|Erev Yom Kippur
20290919|h,y|Yom Kippur
20290921|c|
20290922|h|Parshas Ha'azinu
20290923|c|Erev Sukkos
20290924|t,y|Sukkos I
20290925|h,y|Sukkos II
20290926||Sukkos III (Chol Hamoed)
20290927||Sukkos IV (Chol Hamoed)
20290928|c|Sukkos V (Chol Hamoed)
20290929|h|Sukkos VI (Chol Hamoed)
20290930|c|Sukkos VII (Hoshana Raba)
20291001|t,y|Shmini Atzeres
20291002|h,y|Simchas Torah
20291005|c|
20291006|h|Parshas Bereshis
20291009||Rosh Chodesh Cheshvan
20291010||Rosh Chodesh Cheshvan
20291012|c|
20291013|h|Parshas Noach
20291019|c|
20291020|h|Parshas Lech-Lecha
20291026|c|
20291027|h|Parshas Vayera
20291102|c|
20291103|h|Parshas Chayei Sara
20291108||Rosh Chodesh Kislev
20291109|c|
20291110|h|Parshas Toldos
20291116|c|
20291117|h|Parshas Vayetzei
20291123|c|
20291124|h|Parshas Vayishlach
20291130|c|
20291201|h|Parshas Vayeshev;Chanukah: 1 candle tonight
20291202||Chanukah: 2 candles tonight
20291203||Chanukah: 3 candles tonight
20291204||Chanukah: 4 candles tonight
20291205||Chanukah: 5 candles tonight
20291206||Chanukah: 6 candles tonight
20291207|c|Rosh Chodesh Teves;Chanukah: 7 candles tonight
20291208|h|Parshas Miketz;Chanukah: 8 candles tonight
20291209||Chanukah (8th day)
20291214|c|
20291215|h|Parshas Vayigash
20291216|fb,fe|Asara B'Teves
20291221|c|
20291222|h|Parshas Vayechi
20291228|c|
20291229|h|Parshas Shemos
20300104|c|
20300105|h|Parshas Vaera;Rosh Chodesh Sh'vat
20300111|c|
20300112|h|Parshas Bo
20300118|c|
20300119|h|Parshas Beshalach;Shabbos Shirah;Tu BiShvat
20300125|c|
20300126|h|Parshas Yisro
20300201|c|
20300202|h|Parshas Mishpatim
20300203||Rosh Chodesh Adar I
20300204||Rosh Chodesh Adar I
20300208|c|
20300209|h|Parshas Terumah
20300215|c|
20300216|h|Parshas Tetzaveh
20300217||Purim Koton
20300218||Shushan Purim Koton
20300222|c|
20300223|h|Parshas Ki Sisa
20300301|c|
20300302|h|Parshas Vayakhel;Shabbos Shekalim
20300305||Rosh Chodesh Adar II
20300306||Rosh Chodesh Adar II
20300308|c|
20300309|h|Parshas Pekudei
20300315|c|
20300316|h|Parshas Vayikra;Shabbos Zachor
20300318|fb,fe|Ta'anis Esther
20300319||Purim
20300320||Shushan Purim
20300322|c|
20300323|h|Parshas Tzav;Shabbos Parah
20300329|c|
20300330|h|Parshas Shmini;Shabbos HaChodesh
20300404||Rosh Chodesh Nisan
20300405|c|
20300406|h|Parshas Tazria
20300412|c|
20300413|h|Parshas Metzora;Shabbos HaGadol
20300417|c,fb|Ta'anis Bechoros;Erev Pesach
20300418|t,y|Pesach I
20300419|c,y|Pesach II
20300420|h|Pesach III (Chol Hamoed)
20300421||Pesach IV (Chol Hamoed)
20300422||Pesach V (Chol Hamoed)
20300423|c|Pesach VI (Chol Hamoed)
20300424|t,y|Pesach VII
20300425|h,y|Pesach VIII
20300426|c|
20300427|h|Parshas Achrei Mos
20300503|c|Rosh Chodesh Iyyar
20300504|h|Parshas Kedoshim;Rosh Chodesh Iyyar
20300510|c|
20300511|h|Parshas Emor
20300517|c|Pesach Sheni
20300518|h|Parshas Behar
20300521||Lag BaOmer
20300524|c|
20300525|h|Parshas Bechukosai
20300531|c|
20300601|h|Parshas Bamidbar
20300602||Rosh Chodesh Sivan
20300606|c|Erev Shavuos
20300607|c,y|Shavuos I
20300608|h,y|Shavuos II
20300614|c|
20300615|h|Parshas Nasso
20300621|c|
20300622|h|Parshas Beha'aloscha
20300628|c|
20300629|h|Parshas Sh'lach
20300701||Rosh Chodesh Tamuz
20300702||Rosh Chodesh Tamuz
20300705|c|
20300706|h|Parshas Korach
20300712|c|
20300713|h|Parshas Chukas-Balak
20300718|fb,fe|Tzom Tammuz
20300719|c|
20300720|h|Parshas Pinchas
20300726|c|
20300727|h|Parshas Matos-Masei
20300731||Rosh Chodesh Av
20300802|c|
20300803|h|Parshas Devarim;Shabbos Chazon
20300807|fn|Erev Tish'a B'Av
20300808|fe|Tish'a B'Av
20300809|c|
20300810|h|Parshas Vaeschanan;Shabbos Nachamu
20300814||Tu B'Av
20300816|c|
20300817|h|Parshas Eikev
20300823|c|
20300824|h|Parshas Re'eh
20300829||Rosh Chodesh Elul
20300830|c|Rosh Hashana LaBeheimos;Rosh Chodesh Elul
20300831|h|Parshas Shoftim
20300906|c|
20300907|h|Parshas Ki Seitzei
20300913|c|
20300914|h|Parshas Ki Savo
20300920|c|
20300921|h|Parshas Nitzavim-Vayeilech;Leil Selichos
20300927|c|Erev Rosh Hashana
20300928|t,y|Rosh Hashana 5791
20300929|h,y|Rosh Hashana II
20300930|fb,fe|Tzom Gedaliah
20301004|c|
20301005|h|Parshas Ha'azinu;Shabbos Shuvah
20301006|c|Erev Yom Kippur
20301007|h,y|Yom Kippur
20301011|c|Erev Sukkos
20301012|t,y|Sukkos I
20301013|h,y|Sukkos II
20301014||Sukkos III (Chol Hamoed)
20301015||Sukkos IV (Chol Hamoed)
20301016||Sukkos V (Chol Hamoed)
20301017||Sukkos VI (Chol Hamoed)
20301018|c|Sukkos VII (Hoshana Raba)
20301019|t,y|Shmini Atzeres
20301020|h,y|Simchas Torah
20301025|c|
20301026|h|Parshas Bereshis
20301027||Rosh Chodesh Cheshvan
20301028||Rosh Chodesh Cheshvan
20301101|c|
20301102|h|Parshas Noach
20301108|c|
20301109|h|Parshas Lech-Lecha
20301115|c|
20301116|h|Parshas Vayera
20301122|c|
20301123|h|Parshas Chayei Sara
20301126||Rosh Chodesh Kislev
20301127||Rosh Chodesh Kislev
20301129|c|
20301130|h|Parshas Toldos
20301206|c|
20301207|h|Parshas Vayetzei
20301213|c|
20301214|h|Parshas Vayishlach
20301220|c|Chanukah: 1 candle tonight
20301221|h|Parshas Vayeshev;Chanukah: 2 candles tonight
20301222||Chanukah: 3 candles tonight
20301223||Chanukah: 4 candles tonight
20301224||Chanukah: 5 candles tonight
20301225||Chanukah: 6 candles tonight
20301226||Rosh Chodesh Teves;Chanukah: 7 candles tonight
20301227|c|Rosh Chodesh Teves;Chanukah: 8 candles tonight
20301228|h|Parshas Miketz;Chanukah (8th day)
20310103|c|
20310104|h|Parshas Vayigash
20310105|fb,fe|Asara B'Teves
20310110|c|
20310111|h|Parshas Vayechi
20310117|c|
20310118|h|Parshas Shemos
20310124|c|
20310125|h|Parshas Vaera;Rosh Chodesh Sh'vat
20310131|c|
20310201|h|Parshas Bo
20310207|c|
20310208|h|Parshas Beshalach;Shabbos Shirah;Tu BiShvat
20310214|c|
20310215|h|Parshas Yisro
20310221|c|
20310222|h|Parshas Mishpatim;Shabbos Shekalim
20310223||Rosh Chodesh Adar
20310224||Rosh Chodesh Adar
20310228|c|
20310301|h|Parshas Terumah
20310306|fb,fe|Ta'anis Esther
20310307|c|
20310308|h|Parshas Tetzaveh;Shabbos Zachor
20310309||Purim
20310310||Shushan Purim
20310314|c|
20310315|h|Parshas Ki Sisa;Shabbos Parah
20310321|c|
20310322|h|Parshas Vayakhel-Pekudei;Shabbos HaChodesh
20310325||Rosh Chodesh Nisan
20310328|c|
20310329|h|Parshas Vayikra
20310404|c|
20310405|h|Parshas Tzav;Shabbos HaGadol
20310407|c,fb|Ta'anis Bechoros;Erev Pesach
20310408|t,y|Pesach I
20310409|h,y|Pesach II
20310410||Pesach III (Chol Hamoed)
20310411|c|Pesach IV (Chol Hamoed)
20310412|h|Pesach V (Chol Hamoed)
20310413|c|Pesach VI (Chol Hamoed)
20310414|t,y|Pesach VII
20310415|h,y|Pesach VIII
20310418|c|
20310419|h|Parshas Shmini
20310423||Rosh Chodesh Iyyar
20310424||Rosh Chodesh Iyyar
20310425|c|
20310426|h|Parshas Tazria-Metzora
20310502|c|
20310503|h|Parshas Achrei Mos-Kedoshim
20310507||Pesach Sheni
20310509|c|
20310510|h|Parshas Emor
20310511||Lag BaOmer
20310516|c|
20310517|h|Parshas Behar-Bechukosai
20310523|c|Rosh Chodesh Sivan
20310524|h|Parshas Bamidbar
20310527|c|Erev Shavuos
20310528|t,y|Shavuos I
20310529|h,y|Shavuos II
20310530|c|
20310531|h|Parshas Nasso
20310606|c|
20310607|h|Parshas Beha'aloscha
20310613|c|
20310614|h|Parshas Sh'lach
20310620|c|
20310621|h|Parshas Korach;Rosh Chodesh Tamuz
20310622||Rosh Chodesh Tamuz
20310627|c|
20310628|h|Parshas Chukas
20310704|c|
20310705|h|Parshas Balak
20310708|fb,fe|Tzom Tammuz
20310711|c|
20310712|h|Parshas Pinchas
20310718|c|
20310719|h|Parshas Matos-Masei
20310721||Rosh Chodesh Av
20310725|c|
20310726|h|Parshas Devarim;Shabbos Chazon
20310728|fn|Erev Tish'a B'Av
20310729|fe|Tish'a B'Av
20310801|c|
20310802|h|Parshas Vaeschanan;Shabbos Nachamu
20310804||Tu B'Av
20310808|c|
20310809|h|Parshas Eikev
20310815|c|
20310816|h|Parshas Re'eh
20310819||Rosh Chodesh Elul
20310820||Rosh Hashana LaBeheimos;Rosh Chodesh Elul
20310822|c|
20310823|h|Parshas Shoftim
20310829|c|
20310830|h|Parshas Ki Seitzei
20310905|c|
20310906|h|Parshas Ki Savo
20310912|c|
20310913|h|Parshas Nitzavim-Vayeilech;Leil Selichos
20310917|c|Erev Rosh Hashana
20310918|t,y|Rosh Hashana 5792
20310919|c,y|Rosh Hashana II
20310920|h|Parshas Ha'azinu;Shabbos Shuvah
20310921|fb,fe|Tzom Gedaliah
20310926|c|Erev Yom Kippur
20310927|h,y|Yom Kippur
20311001|c|Erev Sukkos
20311002|t,y|Sukkos I
20311003|c,y|Sukkos II
20311004|h|Sukkos III (Chol Hamoed)
20311005||Sukkos IV (Chol Hamoed)
20311006||Sukkos V (Chol Hamoed)
20311007||Sukkos VI (Chol Hamoed)
20311008|c|Sukkos VII (Hoshana Raba)
20311009|t,y|Shmini Atzeres
20311010|c,y|Simchas Torah
20311011|h|Parshas Bereshis
20311017|c|Rosh Chodesh Cheshvan
20311018|h|Parshas Noach;Rosh Chodesh Cheshvan
20311024|c|
20311025|h|Parshas Lech-Lecha
20311031|c|
20311101|h|Parshas Vayera
20311107|c|
20311108|h|Parshas Chayei Sara
20311114|c|
20311115|h|Parshas Toldos
20311116||Rosh Chodesh Kislev
20311121|c|
20311122|h|Parshas Vayetzei
20311128|c|
20311129|h|Parshas Vayishlach
20311205|c|
20311206|h|Parshas Vayeshev
20311209||Chanukah: 1 candle tonight
20311210||Chanukah: 2 candles tonight
20311211||Chanukah: 3 candles tonight
20311212|c|Chanukah: 4 candles tonight
20311213|h|Parshas Miketz;Chanukah: 5 candles tonight
20311214||Chanukah: 6 candles tonight
20311215||Rosh Chodesh Teves;Chanukah: 7 candles tonight
20311216||Rosh Chodesh Teves;Chanukah: 8 candles tonight
20311217||Chanukah (8th day)
20311219|c|
20311220|h|Parshas Vayigash
20311225|fb,fe|Asara B'Teves
20311226|c|
20311227|h|Parshas Vayechi
20320102|c|
20320103|h|Parshas Shemos
20320109|c|
20320110|h|Parshas Vaera
20320114||Rosh Chodesh Sh'vat
20320116|c|
20320117|h|Parshas Bo
20320123|c|
20320124|h|Parshas Beshalach;Shabbos Shirah
20320128||Tu BiShvat
20320130|c|
20320131|h|Parshas Yisro
20320206|c|
20320207|h|Parshas Mishpatim;Shabbos Shekalim
20320212||Rosh Chodesh Adar
20320213|c|Rosh Chodesh Adar
20320214|h|Parshas Terumah
20320220|c|
20320221|h|Parshas Tetzaveh;Shabbos Zachor
20320225|fb,fe|Ta'anis Esther
20320226||Purim
20320227|c|Shushan Purim
20320228|h|Parshas Ki Sisa
20320305|c|
20320306|h|Parshas Vayakhel-Pekudei;Shabbos Parah
20320312|c|
20320313|h|Parshas Vayikra;Shabbos HaChodesh;Rosh Chodesh Nisan
20320319|c|
20320320|h|Parshas Tzav;Shabbos HaGadol
20320326|c,fb|Ta'anis Bechoros;Erev Pesach
20320327|t,y|Pesach I
20320328|h,y|Pesach II
20320329||Pesach III (Chol Hamoed)
20320330||Pesach IV (Chol Hamoed)
20320331||Pesach V (Chol Hamoed)
20320401|c|Pesach VI (Chol Hamoed)
20320402|c,y|Pesach VII
20320403|h,y|Pesach VIII
20320409|c|
20320410|h|Parshas Shmini
20320411||Rosh Chodesh Iyyar
20320412||Rosh Chodesh Iyyar
20320416|c|
20320417|h|Parshas Tazria-Metzora
20320423|c|
20320424|h|Parshas Achrei Mos-Kedoshim
20320425||Pesach Sheni
20320429||Lag BaOmer
20320430|c|
20320501|h|Parshas Emor
20320507|c|
20320508|h|Parshas Behar-Bechukosai
20320511||Rosh Chodesh Sivan
20320514|c|
20320515|t|Parshas Bamidbar;Erev Shavuos
20320516|t,y|Shavuos I
20320517|h,y|Shavuos II
20320521|c|
20320522|h|Parshas Nasso
20320528|c|
20320529|h|Parshas Beha'aloscha
20320604|c|
20320605|h|Parshas Sh'lach
20320609||Rosh Chodesh Tamuz
20320610||Rosh Chodesh Tamuz
20320611|c|
20320612|h|Parshas Korach
20320618|c|
20320619|h|Parshas Chukas
20320625|c|
20320626|h|Parshas Balak
20320627|fb,fe|Tzom Tammuz
20320702|c|
20320703|h|Parshas Pinchas
20320709|c|Rosh Chodesh Av
20320710|h|Parshas Matos-Masei
20320716|c|
20320717|fn,h|Parshas Devarim;Shabbos Chazon;Erev Tish'a B'Av
20320718|fe|Tish'a B'Av (observed)
20320723|c|Tu B'Av
20320724|h|Parshas Vaeschanan;Shabbos Nachamu
20320730|c|
20320731|h|Parshas Eikev
20320806|c|
20320807|h|Parshas Re'eh;Rosh Chodesh Elul
20320808||Rosh Hashana LaBeheimos;Rosh Chodesh Elul
20320813|c|
20320814|h|Parshas Shoftim
20320820|c|
20320821|h|Parshas Ki Seitzei
20320827|c|
20320828|h|Parshas Ki Savo;Leil Selichos
20320903|c|
20320904|h|Parshas Nitzavim
20320905|c|Erev Rosh Hashana
20320906|t,y|Rosh Hashana 5793
20320907|h,y|Rosh Hashana II
20320908|fb,fe|Tzom Gedaliah
20320910|c|
20320911|h|Parshas Vayeilech;Shabbos Shuvah
20320914|c|Erev Yom Kippur
20320915|h,y|Yom Kippur
20320917|c|
20320918|h|Parshas Ha'azinu
20320919|c|Erev Sukkos
20320920|t,y|Sukkos I
20320921|h,y|Sukkos II
20320922||Sukkos III (Chol Hamoed)
20320923||Sukkos IV (Chol Hamoed)
20320924|c|Sukkos V (Chol Hamoed)
20320925|h|Sukkos VI (Chol Hamoed)
20320926|c|Sukkos VII (Hoshana Raba)
20320927|t,y|Shmini Atzeres
20320928|h,y|Simchas Torah
20321001|c|
20321002|h|Parshas Bereshis
20321005||Rosh Chodesh Cheshvan
20321006||Rosh Chodesh Cheshvan
20321008|c|
20321009|h|Parshas Noach
20321015|c|
20321016|h|Parshas Lech-Lecha
20321022|c|
20321023|h|Parshas Vayera
20321029|c|
20321030|h|Parshas Chayei Sara
20321104||Rosh Chodesh Kislev
20321105|c|
20321106|h|Parshas Toldos
20321112|c|
20321113|h|Parshas Vayetzei
20321119|c|
20321120|h|Parshas Vayishlach
20321126|c|
20321127|h|Parshas Vayeshev;Chanukah: 1 candle tonight
20321128||Chanukah: 2 candles tonight
20321129||Chanukah: 3 candles tonight
20321130||Chanukah: 4 candles tonight
20321201||Chanukah: 5 candles tonight
20321202||Chanukah: 6 candles tonight
20321203|c|Rosh Chodesh Teves;Chanukah: 7 candles tonight
20321204|h|Parshas Miketz;Chanukah: 8 candles tonight
20321205||Chanukah (8th day)
20321210|c|
20321211|h|Parshas Vayigash
20321212|fb,fe|Asara B'Teves
20321217|c|
20321218|h|Parshas Vayechi
20321224|c|
20321225|h|Parshas Shemos
20321231|c|
20330101|h|Parshas Vaera;Rosh Chodesh Sh'vat
20330107|c|
20330108|h|Parshas Bo
20330114|c|
20330115|h|Parshas Beshalach;Shabbos Shirah;Tu BiShvat
20330121|c|
20330122|h|Parshas Yisro
20330128|c|
20330129|h|Parshas Mishpatim
20330130||Rosh Chodesh Adar I
20330131||Rosh Chodesh Adar I
20330204|c|
20330205|h|Parshas Terumah
20330211|c|
20330212|h|Parshas Tetzaveh
20330213||Purim Koton
20330214||Shushan Purim Koton
20330218|c|
20330219|h|Parshas Ki Sisa
20330225|c|
20330226|h|Parshas Vayakhel;Shabbos Shekalim
20330301||Rosh Chodesh Adar II
20330302||Rosh Chodesh Adar II
20330304|c|
20330305|h|Parshas Pekudei
20330311|c|
20330312|h|Parshas Vayikra;Shabbos Zachor
20330314|fb,fe|Ta'anis Esther
20330315||Purim
20330316||Shushan Purim
20330318|c|
20330319|h|Parshas Tzav;Shabbos Parah
20330325|c|
20330326|h|Parshas Shmini;Shabbos HaChodesh
20330331||Rosh Chodesh Nisan
20330401|c|
20330402|h|Parshas Tazria
20330408|c|
20330409|h|Parshas Metzora;Shabbos HaGadol
20330413|c,fb|Ta'anis Bechoros;Erev Pesach
20330414|t,y|Pesach I
20330415|c,y|Pesach II
20330416|h|Pesach III (Chol Hamoed)
20330417||Pesach IV (Chol Hamoed)
20330418||Pesach V (Chol Hamoed)
20330419|c|Pesach VI (Chol Hamoed)
20330420|t,y|Pesach VII
20330421|h,y|Pesach VIII
20330422|c|
20330423|h|Parshas Achrei Mos
20330429|c|Rosh Chodesh Iyyar
20330430|h|Parshas Kedoshim;Rosh Chodesh Iyyar
20330506|c|
20330507|h|Parshas Emor
20330513|c|Pesach Sheni
20330514|h|Parshas Behar
20330517||Lag BaOmer
20330520|c|
20330521|h|Parshas Bechukosai
20330527|c|
20330528|h|Parshas Bamidbar
20330529||Rosh Chodesh Sivan
20330602|c|Erev Shavuos
20330603|c,y|Shavuos I
20330604|h,y|Shavuos II
20330610|c|
20330611|h|Parshas Nasso
20330617|c|
20330618|h|Parshas Beha'aloscha
20330624|c|
20330625|h|Parshas Sh'lach
20330627||Rosh Chodesh Tamuz
20330628||Rosh Chodesh Tamuz
20330701|c|
20330702|h|Parshas Korach
20330708|c|
20330709|h|Parshas Chukas-Balak
20330714|fb,fe|Tzom Tammuz
20330715|c|
20330716|h|Parshas Pinchas
20330722|c|
20330723|h|Parshas Matos-Masei
20330727||Rosh Chodesh Av
20330729|c|
20330730|h|Parshas Devarim;Shabbos Chazon
20330803|fn|Erev Tish'a B'Av
20330804|fe|Tish'a B'Av
20330805|c|
20330806|h|Parshas Vaeschanan;Shabbos Nachamu
20330810||Tu B'Av
20330812|c|
20330813|h|Parshas Eikev
20330819|c|
20330820|h|Parshas Re'eh
20330825||Rosh Chodesh Elul
20330826|c|Rosh Hashana LaBeheimos;Rosh Chodesh Elul
20330827|h|Parshas Shoftim
20330902|c|
20330903|h|Parshas Ki Seitzei
20330909|c|
20330910|h|Parshas Ki Savo
20330916|c|
20330917|h|Parshas Nitzavim-Vayeilech;Leil Selichos
20330923|c|Erev Rosh Hashana
20330924|t,y|Rosh Hashana 5794
20330925|h,y|Rosh Hashana II
20330926|fb,fe|Tzom Gedaliah
20330930|c|
20331001|h|Parshas Ha'azinu;Shabbos Shuvah
20331002|c|Erev Yom Kippur
20331003|h,y|Yom Kippur
20331007|c|Erev Sukkos
20331008|t,y|Sukkos I
20331009|h,y|Sukkos II
20331010||Sukkos III (Chol Hamoed)
20331011||Sukkos IV (Chol Hamoed)
20331012||Sukkos V (Chol Hamoed)
20331013||Sukkos VI (Chol Hamoed)
20331014|c|Sukkos VII (Hoshana Raba)
20331015|t,y|Shmini Atzeres
20331016|h,y|Simchas Torah
20331021|c|
20331022|h|Parshas Bereshis
20331023||Rosh Chodesh Cheshvan
20331024||Rosh Chodesh Cheshvan
20331028|c|
20331029|h|Parshas Noach
20331104|c|
20331105|h|Parshas Lech-Lecha
20331111|c|
20331112|h|Parshas Vayera
20331118|c|
20331119|h|Parshas Chayei Sara
20331122||Rosh Chodesh Kislev
20331123||Rosh Chodesh Kislev
20331125|c|
20331126|h|Parshas Toldos
20331202|c|
20331203|h|Parshas Vayetzei
20331209|c|
20331210|h|Parshas Vayishlach
20331216|c|Chanukah: 1 candle tonight
20331217|h|Parshas Vayeshev;Chanukah: 2 candles tonight
20331218||Chanukah: 3 candles tonight
20331219||Chanukah: 4 candles tonight
20331220||Chanukah: 5 candles tonight
20331221||Chanukah: 6 candles tonight
20331222||Rosh Chodesh Teves;Chanukah: 7 candles tonight
20331223|c|Rosh Chodesh Teves;Chanukah: 8 candles tonight
20331224|h|Parshas Miketz;Chanukah (8th day)
20331230|c|
20331231|h|Parshas Vayigash
20340101|fb,fe|Asara B'Teves
20340106|c|
20340107|h|Parshas Vayechi
20340113|c|
20340114|h|Parshas Shemos
20340120|c|
20340121|h|Parshas Vaera;Rosh Chodesh Sh'vat
20340127|c|
20340128|h|Parshas Bo
20340203|c|
20340204|h|Parshas Beshalach;Shabbos Shirah;Tu BiShvat
20340210|c|
20340211|h|Parshas Yisro
20340217|c|
20340218|h|Parshas Mishpatim;Shabbos Shekalim
20340219||Rosh Chodesh Adar
20340220||Rosh Chodesh Adar
20340224|c|
20340225|h|Parshas Terumah
20340302|fb,fe|Ta'anis Esther
20340303|c|
20340304|h|Parshas Tetzaveh;Shabbos Zachor
20340305||Purim
20340306||Shushan Purim
20340310|c|
20340311|h|Parshas Ki Sisa;Shabbos Parah
20340317|c|
20340318|h|Parshas Vayakhel-Pekudei;Shabbos HaChodesh
20340321||Rosh Chodesh Nisan
20340324|c|
20340325|h|Parshas Vayikra
20340331|c|
20340401|h|Parshas Tzav;Shabbos HaGadol
20340403|c,fb|Ta'anis Bechoros;Erev Pesach
20340404|t,y|Pesach I
20340405|h,y|Pesach II
20340406||Pesach III (Chol Hamoed)
20340407|c|Pesach IV (Chol Hamoed)
20340408|h|Pesach V (Chol Hamoed)
20340409|c|Pesach VI (Chol Hamoed)
20340410|t,y|Pesach VII
20340411|h,y|Pesach VIII
20340414|c|
20340415|h|Parshas Shmini
20340419||Rosh Chodesh Iyyar
20340420||Rosh Chodesh Iyyar
20340421|c|
20340422|h|Parshas Tazria-Metzora
20340428|c|
20340429|h|Parshas Achrei Mos-Kedoshim
20340503||Pesach Sheni
20340505|c|
20340506|h|Parshas Emor
20340507||Lag BaOmer
20340512|c|
20340513|h|Parshas Behar-Bechukosai
20340519|c|Rosh Chodesh Sivan
20340520|h|Parshas Bamidbar
20340523|c|Erev Shavuos
20340524|t,y|Shavuos I
20340525|h,y|Shavuos II
20340526|c|
20340527|h|Parshas Nasso
20340602|c|
20340603|h|Parshas Beha'aloscha
20340609|c|
20340610|h|Parshas Sh'lach
20340616|c|
20340617|h|Parshas Korach;Rosh Chodesh Tamuz
20340618||Rosh Chodesh Tamuz
20340623|c|
20340624|h|Parshas Chukas
20340630|c|
20340701|h|Parshas Balak
20340704|fb,fe|Tzom Tammuz
20340707|c|
20340708|h|Parshas Pinchas
20340714|c|
20340715|h|Parshas Matos-Masei
20340717||Rosh Chodesh Av
20340721|c|
20340722|h|Parshas Devarim;Shabbos Chazon
20340724|fn|Erev Tish'a B'Av
20340725|fe|Tish'a B'Av
20340728|c|
20340729|h|Parshas Vaeschanan;Shabbos Nachamu
20340731||Tu B'Av
20340804|c|
20340805|h|Parshas Eikev
20340811|c|
20340812|h|Parshas Re'eh
20340815||Rosh Chodesh Elul
20340816||Rosh Hashana LaBeheimos;Rosh Chodesh Elul
20340818|c|
20340819|h|Parshas Shoftim
20340825|c|
20340826|h|Parshas Ki Seitzei
20340901|c|
20340902|h|Parshas Ki Savo
20340908|c|
20340909|h|Parshas Nitzavim-Vayeilech;Leil Selichos
20340913|c|Erev Rosh Hashana
20340914|t,y|Rosh Hashana 5795
20340915|c,y|Rosh Hashana II
20340916|h|Parshas Ha'azinu;Shabbos Shuvah
20340917|fb,fe|Tzom Gedaliah
20340922|c|Erev Yom Kippur
20340923|h,y|Yom Kippur
20340927|c|Erev Sukkos
20340928|t,y|Sukkos I
20340929|c,y|Sukkos II
20340930|h|Sukkos III (Chol Hamoed)
20341001||Sukkos IV (Chol Hamoed)
20341002||Sukkos V (Chol Hamoed)
20341003||Sukkos VI (Chol Hamoed)
20341004|c|Sukkos VII (Hoshana Raba)
20341005|t,y|Shmini Atzeres
20341006|c,y|Simchas Torah
20341007|h|Parshas Bereshis
20341013|c|Rosh Chodesh Cheshvan
20341014|h|Parshas Noach;Rosh Chodesh Cheshvan
20341020|c|
20341021|h|Parshas Lech-Lecha
20341027|c|
20341028|h|Parshas Vayera
20341103|c|
20341104|h|Parshas Chayei Sara
20341110|c|
20341111|h|Parshas Toldos
20341112||Rosh Chodesh Kislev
20341113||Rosh Chodesh Kislev
20341117|c|
20341118|h|Parshas Vayetzei
20341124|c|
20341125|h|Parshas Vayishlach
20341201|c|
20341202|h|Parshas Vayeshev
20341206||Chanukah: 1 candle tonight
20341207||Chanukah: 2 candles tonight
20341208|c|Chanukah: 3 candles tonight
20341209|h|Parshas Miketz;Chanukah: 4 candles tonight
20341210||Chanukah: 5 candles tonight
20341211||Chanukah: 6 candles tonight
20341212||Rosh Chodesh Teves;Chanukah: 7 candles tonight
20341213||Rosh Chodesh Teves;Chanukah: 8 candles tonight
20341214||Chanukah (8th day)
20341215|c|
20341216|h|Parshas Vayigash
20341222|c,fb|Asara B'Teves
20341223|h|Parshas Vayechi
20341229|c|
20341230|h|Parshas Shemos
20350105|c|
20350106|h|Parshas Vaera
20350111||Rosh Chodesh Sh'vat
20350112|c|
20350113|h|Parshas Bo
20350119|c|
20350120|h|Parshas Beshalach;Shabbos Shirah
20350125||Tu BiShvat
20350126|c|
20350127|h|Parshas Yisro
20350202|c|
20350203|h|Parshas Mishpatim
20350209|c|Rosh Chodesh Adar I
20350210|h|Parshas Terumah;Rosh Chodesh Adar I
20350216|c|
20350217|h|Parshas Tetzaveh
20350223|c|Purim Koton
20350224|h|Parshas Ki Sisa;Shushan Purim Koton
20350302|c|
20350303|h|Parshas Vayakhel
20350309|c|
20350310|h|Parshas Pekudei;Shabbos Shekalim
20350311||Rosh Chodesh Adar II
20350312||Rosh Chodesh Adar II
20350316|c|
20350317|h|Parshas Vayikra
20350322|fb,fe|Ta'anis Esther
20350323|c|
20350324|h|Parshas Tzav;Shabbos Zachor
20350325||Purim
20350326||Shushan Purim
20350330|c|
20350331|h|Parshas Shmini;Shabbos Parah
20350406|c|
20350407|h|Parshas Tazria;Shabbos HaChodesh
20350410||Rosh Chodesh Nisan
20350413|c|
20350414|h|Parshas Metzora
20350420|c|
20350421|h|Parshas Achrei Mos;Shabbos HaGadol
20350423|c,fb|Ta'anis Bechoros;Erev Pesach
20350424|t,y|Pesach I
20350425|h,y|Pesach II
20350426||Pesach III (Chol Hamoed)
20350427|c|Pesach IV (Chol Hamoed)
20350428|h|Pesach V (Chol Hamoed)
20350429|c|Pesach VI (Chol Hamoed)
20350430|t,y|Pesach VII
20350501|h,y|Pesach VIII
20350504|c|
20350505|h|Parshas Kedoshim
20350509||Rosh Chodesh Iyyar
20350510||Rosh Chodesh Iyyar
20350511|c|
20350512|h|Parshas Emor
20350518|c|
20350519|h|Parshas Behar
20350523||Pesach Sheni
20350525|c|
20350526|h|Parshas Bechukosai
20350527||Lag BaOmer
20350601|c|
20350602|h|Parshas Bamidbar
20350608|c|Rosh Chodesh Sivan
20350609|h|Parshas Nasso
20350612|c|Erev Shavuos
20350613|t,y|Shavuos I
20350614|h,y|Shavuos II
20350615|c|
20350616|h|Parshas Beha'aloscha
20350622|c|
20350623|h|Parshas Sh'lach
20350629|c|
20350630|h|Parshas Korach
20350706|c|
20350707|h|Parshas Chukas;Rosh Chodesh Tamuz
20350708||Rosh Chodesh Tamuz
20350713|c|
20350714|h|Parshas Balak
20350720|c|
20350721|h|Parshas Pinchas
20350724|fb,fe|Tzom Tammuz
20350727|c|
20350728|h|Parshas Matos
20350803|c|
20350804|h|Parshas Masei
20350806||Rosh Chodesh Av
20350810|c|
20350811|h|Parshas Devarim;Shabbos Chazon
20350813|fn|Erev Tish'a B'Av
20350814|fe|Tish'a B'Av
20350817|c|
20350818|h|Parshas Vaeschanan;Shabbos Nachamu
20350820||Tu B'Av
20350824|c|
20350825|h|Parshas Eikev
20350831|c|
20350901|h|Parshas Re'eh
20350904||Rosh Chodesh Elul
20350905||Rosh Hashana LaBeheimos;Rosh Chodesh Elul
20350907|c|
20350908|h|Parshas Shoftim
20350914|c|
20350915|h|Parshas Ki Seitzei
20350921|c|
20350922|h|Parshas Ki Savo
20350928|c|
20350929|h|Parshas Nitzavim-Vayeilech;Leil Selichos
20351003|c|Erev Rosh Hashana
20351004|t,y|Rosh Hashana 5796
20351005|c,y|Rosh Hashana II
20351006|h|Parshas Ha'azinu;Shabbos Shuvah
20351007|fb,fe|Tzom Gedaliah
20351012|c|Erev Yom Kippur
20351013|h,y|Yom Kippur
20351017|c|Erev Sukkos
20351018|t,y|Sukkos I
20351019|c,y|Sukkos II
20351020|h|Sukkos III (Chol Hamoed)
20351021||Sukkos IV (Chol Hamoed)
20351022||Sukkos V (Chol Hamoed)
20351023||Sukkos VI (Chol Hamoed)
20351024|c|Sukkos VII (Hoshana Raba)
20351025|t,y|Shmini Atzeres
20351026|c,y|Simchas Torah
20351027|h|Parshas Bereshis
20351102|c|Rosh Chodesh Cheshvan
20351103|h|Parshas Noach;Rosh Chodesh Cheshvan
20351109|c|
20351110|h|Parshas Lech-Lecha
20351116|c|
20351117|h|Parshas Vayera
20351123|c|
20351124|h|Parshas Chayei Sara
20351130|c|
20351201|h|Parshas Toldos
20351202||Rosh Chodesh Kislev
20351207|c|
20351208|h|Parshas Vayetzei
20351214|c|
20351215|h|Parshas Vayishlach
20351221|c|
20351222|h|Parshas Vayeshev
20351225||Chanukah: 1 candle tonight
20351226||Chanukah: 2 candles tonight
20351227||Chanukah: 3 candles tonight
20351228|c|Chanukah: 4 candles tonight
20351229|h|Parshas Miketz;Chanukah: 5 candles tonight
20351230||Chanukah: 6 candles tonight
20351231||Rosh Chodesh Teves;Chanukah: 7 candles tonight
20360101||Rosh Chodesh Teves;Chanukah: 8 candles tonight
20360102||Chanukah (8th day)
20360104|c|
20360105|h|Parshas Vayigash
20360110|fb,fe|Asara B'Teves
20360111|c|
20360112|h|Parshas Vayechi
20360118|c|
20360119|h|Parshas Shemos
20360125|c|
20360126|h|Parshas Vaera
20360130||Rosh Chodesh Sh'vat
20360201|c|
20360202|h|Parshas Bo
20360208|c|
20360209|h|Parshas Beshalach;Shabbos Shirah
20360213||Tu BiShvat
20360215|c|
20360216|h|Parshas Yisro
20360222|c|
20360223|h|Parshas Mishpatim;Shabbos Shekalim
20360228||Rosh Chodesh Adar
20360229|c|Rosh Chodesh Adar
20360301|h|Parshas Terumah
20360307|c|
20360308|h|Parshas Tetzaveh;Shabbos Zachor
20360312|fb,fe|Ta'anis Esther
20360313||Purim
20360314|c|Shushan Purim
20360315|h|Parshas Ki Sisa
20360321|c|
20360322|h|Parshas Vayakhel-Pekudei;Shabbos Parah
20360328|c|
20360329|h|Parshas Vayikra;Shabbos HaChodesh;Rosh Chodesh Nisan
20360404|c|
20360405|h|Parshas Tzav;Shabbos HaGadol
20360411|c,fb|Ta'anis Bechoros;Erev Pesach
20360412|t,y|Pesach I
20360413|h,y|Pesach II
20360414||Pesach III (Chol Hamoed)
20360415||Pesach IV (Chol Hamoed)
20360416||Pesach V (Chol Hamoed)
20360417|c|Pesach VI (Chol Hamoed)
20360418|c,y|Pesach VII
20360419|h,y|Pesach VIII
20360425|c|
20360426|h|Parshas Shmini
20360427||Rosh Chodesh Iyyar
20360428||Rosh Chodesh Iyyar
20360502|c|
20360503|h|Parshas Tazria-Metzora
20360509|c|
20360510|h|Parshas Achrei Mos-Kedoshim
20360511||Pesach Sheni
20360515||Lag BaOmer
20360516|c|
20360517|h|Parshas Emor
20360523|c|
20360524|h|Parshas Behar-Bechukosai
20360527||Rosh Chodesh Sivan
20360530|c|
20360531|t|Parshas Bamidbar;Erev Shavuos
20360601|t,y|Shavuos I
20360602|h,y|Shavuos II
20360606|c|
20360607|h|Parshas Nasso
20360613|c|
20360614|h|Parshas Beha'aloscha
20360620|c|
20360621|h|Parshas Sh'lach
20360625||Rosh Chodesh Tamuz
20360626||Rosh Chodesh Tamuz
20360627|c|
20360628|h|Parshas Korach
20360704|c|
20360705|h|Parshas Chukas
20360711|c|
20360712|h|Parshas Balak
20360713|fb,fe|Tzom Tammuz
20360718|c|
20360719|h|Parshas Pinchas
20360725|c|Rosh Chodesh Av
20360726|h|Parshas Matos-Masei
20360801|c|
20360802|fn,h|Parshas Devarim;Shabbos Chazon;Erev Tish'a B'Av
20360803|fe|Tish'a B'Av (observed)
20360808|c|Tu B'Av
20360809|h|Parshas Vaeschanan;Shabbos Nachamu
20360815|c|
20360816|h|Parshas Eikev
20360822|c|
20360823|h|Parshas Re'eh;Rosh Chodesh Elul
20360824||Rosh Hashana LaBeheimos;Rosh Chodesh Elul
20360829|c|
20360830|h|Parshas Shoftim
20360905|c|
20360906|h|Parshas Ki Seitzei
20360912|c|
20360913|h|Parshas Ki Savo;Leil Selichos
20360919|c|
20360920|h|Parshas Nitzavim
20360921|c|Erev Rosh Hashana
20360922|t,y|Rosh Hashana 5797
20360923|h,y|Rosh Hashana II
20360924|fb,fe|Tzom Gedaliah
20360926|c|
20360927|h|Parshas Vayeilech;Shabbos Shuvah
20360930|c|Erev Yom Kippur
20361001|h,y|Yom Kippur
20361003|c|
20361004|h|Parshas Ha'azinu
20361005|c|Erev Sukkos
20361006|t,y|Sukkos I
20361007|h,y|Sukkos II
20361008||Sukkos III (Chol Hamoed)
20361009||Sukkos IV (Chol Hamoed)
20361010|c|Sukkos V (Chol Hamoed)
20361011|h|Sukkos VI (Chol Hamoed)
20361012|c|Sukkos VII (Hoshana Raba)
20361013|t,y|Shmini Atzeres
20361014|h,y|Simchas Torah
20361017|c|
20361018|h|Parshas Bereshis
20361021||Rosh Chodesh Cheshvan
20361022||Rosh Chodesh Cheshvan
20361024|c|
20361025|h|Parshas Noach
20361031|c|
20361101|h|Parshas Lech-Lecha
20361107|c|
20361108|h|Parshas Vayera
20361114|c|
20361115|h|Parshas Chayei Sara
20361120||Rosh Chodesh Kislev
20361121|c|
20361122|h|Parshas Toldos
20361128|c|
20361129|h|Parshas Vayetzei
20361205|c|
20361206|h|Parshas Vayishlach
20361212|c|
20361213|h|Parshas Vayeshev;Chanukah: 1 candle tonight
20361214||Chanukah: 2 candles tonight
20361215||Chanukah: 3 candles tonight
20361216||Chanukah: 4 candles tonight
20361217||Chanukah: 5 candles tonight
20361218||Chanukah: 6 candles tonight
20361219|c|Rosh Chodesh Teves;Chanukah: 7 candles tonight
20361220|h|Parshas Miketz;Chanukah: 8 candles tonight
20361221||Chanukah (8th day)
20361226|c|
20361227|h|Parshas Vayigash
20361228|fb,fe|Asara B'Teves
"""#
}
