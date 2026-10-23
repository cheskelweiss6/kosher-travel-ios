// Data for the Zmanim card, ported unchanged from the website (read-only sources):
//   src/lib/zmanim/places.ts       TZS, CITY_GEO (id|lat|lng|tz index), STATE_MAIN (state|main city|lat|lng|tz index)
//   src/components/stories/storyCities.ts  STORY_CITIES (id|name|sub|lat|lon), used by the location search
//   src/lib/zmanim/calendarData.ts CAL_DATA (diaspora 2026-01-02 .. 2036-12-28): YYYYMMDD|flags|names
// Kept as text and parsed once on first use, so the compiler never type-checks a huge literal.
import Foundation

enum ZmanimData {
    static let timeZones: [String] = [
        "Africa/Johannesburg",
        "America/Anchorage",
        "America/Anguilla",
        "America/Antigua",
        "America/Aruba",
        "America/Asuncion",
        "America/Barbados",
        "America/Belize",
        "America/Bogota",
        "America/Boise",
        "America/Cancun",
        "America/Cayman",
        "America/Chicago",
        "America/Costa_Rica",
        "America/Curacao",
        "America/Denver",
        "America/Detroit",
        "America/Dominica",
        "America/Grand_Turk",
        "America/Grenada",
        "America/Guadeloupe",
        "America/Guatemala",
        "America/Havana",
        "America/Indiana/Indianapolis",
        "America/Jamaica",
        "America/Juneau",
        "America/Kentucky/Louisville",
        "America/Kralendijk",
        "America/Los_Angeles",
        "America/Lower_Princes",
        "America/Managua",
        "America/Marigot",
        "America/Martinique",
        "America/Mazatlan",
        "America/Mexico_City",
        "America/Montserrat",
        "America/Nassau",
        "America/New_York",
        "America/Panama",
        "America/Phoenix",
        "America/Port-au-Prince",
        "America/Port_of_Spain",
        "America/Puerto_Rico",
        "America/Santo_Domingo",
        "America/Sitka",
        "America/St_Barthelemy",
        "America/St_Kitts",
        "America/St_Lucia",
        "America/St_Thomas",
        "America/St_Vincent",
        "America/Tegucigalpa",
        "America/Tortola",
        "Asia/Jerusalem",
        "Atlantic/Bermuda",
        "Pacific/Honolulu"
    ]

    struct Geo { let lat: Double; let lng: Double; let tz: String }
    struct StateMain { let city: String; let lat: Double; let lng: Double; let tz: String }
    struct StoryCity { let id: String; let name: String; let sub: String; let lat: Double?; let lon: Double? }

    /// CITY_GEO, keyed by the app's destination id, in the website's order.
    static let cityGeoOrdered: [(String, Geo)] = {
        var out: [(String, Geo)] = []
        for line in cityGeoText.split(separator: "\n") {
            let p = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard p.count == 4, let lat = Double(p[1]), let lng = Double(p[2]), let i = Int(p[3]), i >= 0, i < timeZones.count else { continue }
            out.append((p[0], Geo(lat: lat, lng: lng, tz: timeZones[i])))
        }
        return out
    }()
    static let cityGeo: [String: Geo] = {
        var d: [String: Geo] = [:]
        for (k, g) in cityGeoOrdered where d[k] == nil { d[k] = g }
        return d
    }()

    /// STATE_MAIN in the website's order (the location search lists states in this order).
    static let stateMainOrdered: [(String, StateMain)] = {
        var out: [(String, StateMain)] = []
        for line in stateMainText.split(separator: "\n") {
            let p = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard p.count == 5, let lat = Double(p[2]), let lng = Double(p[3]), let i = Int(p[4]), i >= 0, i < timeZones.count else { continue }
            out.append((p[0], StateMain(city: p[1], lat: lat, lng: lng, tz: timeZones[i])))
        }
        return out
    }()
    static let stateMain: [String: StateMain] = {
        var d: [String: StateMain] = [:]
        for (k, s) in stateMainOrdered where d[k] == nil { d[k] = s }
        return d
    }()

    static let storyCities: [StoryCity] = {
        var out: [StoryCity] = []
        for line in storyCitiesText.split(separator: "\n") {
            let p = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard p.count == 5 else { continue }
            out.append(StoryCity(id: p[0], name: p[1], sub: p[2], lat: Double(p[3]), lon: Double(p[4])))
        }
        return out
    }()

    static let cityGeoText = """
illinois-chicago|41.8756|-87.6244|12
evanston|42.0694|-87.6829|12
alabama-birmingham|33.5207|-86.8024|12
alabama-huntsville|34.7298|-86.5859|12
alabama-mobile|30.6913|-88.0438|12
phoenix|33.4484|-112.0741|39
scottsdale|33.4942|-111.926|39
sedona|34.8689|-111.7614|39
flagstaff|35.1988|-111.6518|39
page|36.9148|-111.4573|39
tucson|32.2229|-110.9748|39
casa-grande|32.8773|-111.7537|39
little-rock|34.7465|-92.2896|12
fayetteville|36.0626|-94.1574|12
los-angeles|34.0537|-118.2428|28
san-francisco|37.7879|-122.4075|28
palm-springs|33.8246|-116.5403|28
san-diego|32.7157|-117.1638|28
santa-barbara|34.4221|-119.7027|28
yosemite|37.8393|-119.5165|28
lake-tahoe|39.0885|-120.0504|28
denver|39.7392|-104.9849|15
aspen|39.1911|-106.8236|15
boulder|40.015|-105.2705|15
colorado-springs|38.834|-104.8253|15
vail|39.6438|-106.3888|15
wilmington|39.7383|-75.5527|37
rehoboth-beach|38.7165|-75.0835|37
hartford|41.7662|-72.6733|37
new-haven|41.3082|-72.9251|37
stamford|41.0534|-73.5387|37
miami|25.7742|-80.1936|37
orlando|28.5421|-81.379|37
tampa|27.945|-82.4583|37
key-west|24.5548|-81.8021|37
fort-lauderdale|26.1223|-80.1434|37
boca-raton|26.3587|-80.0831|37
atlanta|33.7545|-84.3898|37
savannah|32.079|-81.0921|37
honolulu|21.3045|-157.8557|54
maui|20.803|-156.3107|54
kauai|22.0504|-159.5589|54
big-island|19.5896|-155.4487|54
boise|43.6166|-116.2009|9
sun-valley|43.6962|-114.3531|9
coeur-dalene|47.6743|-116.7812|28
indianapolis|39.7683|-86.1584|23
south-bend|41.6834|-86.25|23
bloomington|39.167|-86.5343|23
des-moines|41.5869|-93.6249|12
iowa-city|41.6613|-91.5299|12
overland-park|38.9743|-94.6852|12
wichita|37.6922|-97.3375|12
louisville|38.2542|-85.7594|26
lexington|38.0464|-84.497|37
new-orleans|29.9575|-90.0629|12
baton-rouge|30.4494|-91.187|12
portland-me|45.5202|-122.6742|28
bar-harbor|44.3876|-68.2043|37
baltimore|39.2909|-76.6108|37
annapolis|38.9786|-76.4928|37
ocean-city|38.3315|-75.0874|37
boston|42.3588|-71.0578|37
cape-cod|41.7988|-69.9961|37
detroit|42.3316|-83.0466|16
ann-arbor|42.2814|-83.7485|16
traverse-city|44.7606|-85.6166|16
minneapolis|44.9773|-93.2655|12
duluth|46.7838|-92.1053|12
jackson|32.2999|-90.183|12
biloxi|30.4008|-88.8894|12
st-louis|38.6254|-90.19|12
kansas-city|39.1001|-94.5781|12
branson|36.6441|-93.2169|12
bozeman|45.6794|-111.044|15
kalispell|48.2022|-114.3153|15
omaha|41.2587|-95.9384|12
lincoln|40.8089|-96.7078|12
las-vegas|36.1674|-115.1484|28
reno|39.5262|-119.8127|28
manchester|42.9956|-71.4548|37
portsmouth|43.0751|-70.7602|37
teaneck|40.886|-74.0073|37
lakewood|40.0941|-74.215|37
atlantic-city|39.3643|-74.4229|37
albuquerque|35.0841|-106.651|15
santa-fe|35.6876|-105.9385|15
new-york-city|40.7127|-74.006|37
catskills|42.028|-74.2698|37
monsey|41.118|-74.0594|37
niagara-falls|43.0848|-79.0702|37
rochester|43.1573|-77.6152|37
the-hamptons|40.9543|-72.1983|37
charlotte|35.2272|-80.8431|37
raleigh|35.7804|-78.6391|37
asheville|35.5954|-82.5508|37
outer-banks|35.5669|-75.4688|37
fargo|46.8772|-96.7898|12
bismarck|46.8083|-100.7837|12
cleveland|41.4997|-81.6937|37
columbus|39.9623|-83.0007|37
cincinnati|39.1013|-84.5127|37
oklahoma-city|35.473|-97.5171|12
tulsa|36.1563|-95.9928|12
bend|44.0582|-121.3153|28
philadelphia|39.9527|-75.1635|37
pittsburgh|40.4407|-80.0026|37
poconos|41.0256|-75.6046|37
providence|41.824|-71.4128|37
newport|41.49|-71.3138|37
charleston|32.7884|-79.9399|37
myrtle-beach|33.6956|-78.89|37
hilton-head|32.1618|-80.7513|37
sioux-falls|43.5476|-96.7294|12
rapid-city|44.0806|-103.228|15
nashville|36.1623|-86.7743|12
memphis|35.146|-90.0518|12
gatlinburg|35.7143|-83.5102|37
houston|29.7589|-95.3677|12
austin|30.2649|-97.7474|12
dallas|32.7763|-96.7969|12
san-antonio|29.4246|-98.4951|12
salt-lake-city|40.7596|-111.8868|15
park-city|40.6461|-111.498|15
moab|38.5738|-109.5462|15
zion-national-park|37.3222|-113.0048|15
burlington|44.4762|-73.2129|37
stowe|44.4644|-72.6856|37
richmond|37.5385|-77.4343|37
virginia-beach|36.8497|-75.9761|37
williamsburg|37.2712|-76.7|37
seattle|47.6038|-122.3301|28
spokane|47.6572|-117.4235|28
charleston-wv|38.3506|-81.6333|37
harpers-ferry|39.3234|-77.732|37
milwaukee|43.0386|-87.9091|12
madison|43.0747|-89.3842|12
wisconsin-dells|43.6256|-89.7716|12
jackson-hole|43.6088|-110.738|15
yellowstone|44.6201|-110.5607|15
anchorage|61.2163|-149.8949|1
juneau|58.302|-134.4197|25
fairbanks|64.8378|-147.7167|1
seward|60.1014|-149.4404|1
girdwood|60.9632|-149.1337|1
talkeetna|62.2676|-150.0295|1
denali-national-park|63.7302|-148.8921|1
homer|59.6454|-151.5446|1
whittier|60.7731|-148.6839|1
valdez|61.1299|-146.3494|1
ketchikan|55.3431|-131.6467|44
skagway|59.6226|-135.4094|25
sitka|57.4086|-135.4596|44
dc-washington|38.8898|-77.0403|37
ocho-rios|18.4081|-77.1011|24
jerusalem|31.7788|35.2258|52
san-jose|9.9327|-84.0797|13
manuel-antonio|9.4086|-84.1548|13
la-fortuna|10.4717|-84.6444|13
tamarindo|10.2984|-85.84|13
monteverde|10.2912|-84.8136|13
cape-town|-33.9288|18.4172|0
nassau|25.0782|-77.3383|36
san-juan|18.3842|-66.0534|42
vieques-island|18.1217|-65.4571|42
dorado-beach|18.4731|-66.2827|42
palm-beach|12.5704|-70.0394|4
oranjestad|12.5337|-70.0548|4
eagle-beach|12.5466|-70.0599|4
simpson-bay|18.0397|-63.0972|29
bridgetown|13.0978|-59.6184|6
st-thomas|18.3429|-64.9189|48
charlotte-amalie|18.3369|-64.9622|48
st-john-usvi|18.3356|-64.755|48
cruz-bay|18.3308|-64.7945|48
st-croix-usvi|17.7291|-64.7589|48
christiansted|17.7439|-64.708|48
red-hook|18.3261|-64.8518|48
george-town|19.2923|-81.3795|11
punta-cana|18.5566|-68.3692|43
castries|14.0096|-60.9902|47
guatemala-city|14.6416|-90.5133|21
providenciales|21.8028|-72.1603|18
willemstad|12.1067|-68.9351|14
panama-city|8.9714|-79.5342|38
gustavia|17.8957|-62.8508|45
st-jean-sbh|17.9015|-62.8371|45
san-pedro|17.9204|-87.9622|7
the-valley|18.2146|-63.0518|2
cancun|21.1527|-86.8426|10
cozumel|20.4321|-86.9207|10
playa-del-carmen|20.6463|-87.0808|10
tulum|20.4296|-87.6529|10
cabo-san-lucas|22.8939|-109.9201|33
mexico-city|19.4326|-99.1332|34
isla-mujeres|21.2372|-86.735|10
isla-navidad|19.1796|-104.678|34
antigua-guatemala|14.5568|-90.7337|21
roatan|16.349|-86.4978|50
san-juan-del-sur|11.1944|-85.8598|30
exuma|23.9685|-76.1799|36
eleuthera|25.0885|-76.1346|36
freeport|26.5943|-78.5529|36
st-johns|17.1185|-61.8449|3
english-harbour|17.0089|-61.7636|3
barbuda|17.6219|-61.784|3
hamilton-bermuda|32.3022|-64.7741|53
kralendijk|12.1473|-68.274|27
road-town|18.4258|-64.6231|51
havana|23.1353|-82.359|22
roseau|15.2992|-61.3873|17
san-salvador|-26.2282|-57.1818|5
st-georges-grenada|12.0535|-61.7518|19
pointe-a-pitre|16.2409|-61.5334|20
port-au-prince|18.5473|-72.3396|40
tegucigalpa|14.1058|-87.2047|50
fort-de-france|14.6028|-61.0677|32
brades|16.7899|-62.2099|35
little-corn-island|12.2885|-82.9829|30
managua|12.1547|-86.2737|30
the-bottom|17.6323|-63.2357|27
basseterre|17.2961|-62.7223|46
kingstown|13.1562|-61.228|49
oranjestad-statia|17.4953|-62.9794|27
port-of-spain|10.6573|-61.518|41
san-blas|9.5859|-78.8788|38
santo-domingo|18.4714|-69.8918|43
philipsburg|18.0251|-63.0483|29
grand-canyon|36.0578|-112.1282|39
carmel|36.5553|-121.9233|28
san-juan-islands|48.5371|-123.0907|28
springdale|37.1889|-112.9986|15
key-largo|25.1093|-80.424|37
st-augustine|29.8947|-81.3145|37
telluride|37.9375|-107.8123|15
nantucket|41.2844|-70.0984|37
whitefish|48.4108|-114.3346|15
lake-placid|44.2831|-73.9828|37
gulf-shores|30.2711|-87.6894|12
hot-springs|34.5038|-93.0552|12
eureka-springs|36.4001|-93.7392|12
monterey|36.2231|-121.3877|28
napa-valley|38.4617|-122.3142|28
big-sur|36.1437|-121.5646|28
joshua-tree|34.1234|-116.3129|28
rocky-mountain-np|40.3554|-105.7177|15
mystic|41.356|-71.9573|37
naples|26.1422|-81.7943|37
galena|42.4157|-90.4295|12
salem-ma|42.5214|-70.8957|37
yellowstone-west|44.6632|-111.1012|15
cape-may|39.1765|-74.8012|37
cannon-beach|45.89|-123.9619|28
badlands-np|43.5271|-102.3617|15
great-smoky-mtns|35.6342|-83.4024|37
olympic-np|47.7865|-123.5361|28
new-river-gorge|37.8967|-81.043|37
door-county|44.7616|-87.533|12
yellowstone-wy|44.6201|-110.5607|15
washington-dc|38.8951|-77.0364|37
destin|30.3935|-86.4958|12
chattanooga|35.0457|-85.3095|37
taos|36.4072|-105.5733|15
montego-bay|18.4725|-77.9217|24
negril|18.278|-78.3495|24
virgin-gorda|18.4654|-64.4155|51
ponce|18.0116|-66.614|42
culebra|18.3031|-65.3001|42
nevis|17.1509|-62.5853|46
bequia|13.0165|-61.232|49
marigot|18.0669|-63.0849|31
soufriere|13.8541|-61.0586|47
bentonville|36.3729|-94.2088|12
santa-cruz|37.0501|-121.9906|28
death-valley|36.4229|-116.9137|28
sequoia-np|36.4958|-118.5599|28
breckenridge|39.4829|-106.0465|15
sarasota|27.3366|-82.5309|37
clearwater|27.9659|-82.8001|37
jekyll-island|31.0656|-81.414|37
hilo|19.7074|-155.0816|54
lawrence|38.9719|-95.2359|12
camden-me|44.2155|-69.0852|37
cambridge-ma|42.3656|-71.104|37
provincetown|42.0526|-70.1859|37
mackinac-island|45.8658|-84.6305|16
natchez|31.5604|-91.4032|12
glacier-np|48.6175|-113.7609|15
boulder-city|35.9788|-114.8338|28
north-conway|44.0378|-71.1238|37
princeton|40.3497|-74.6597|37
carlsbad-nm|32.4257|-104.2376|15
brooklyn|40.6526|-73.9497|37
lake-george|43.426|-73.7124|37
boone|36.2188|-81.684|37
astoria|46.1882|-123.832|28
hershey|40.285|-76.6535|37
lancaster-pa|40.038|-76.3057|37
block-island|41.1896|-71.5679|37
greenville-sc|34.8514|-82.3985|37
fort-worth|32.7532|-97.3327|12
fredericksburg|30.2752|-98.872|12
bryce-canyon|37.5708|-112.1856|15
charlottesville|38.0293|-78.4767|37
leavenworth|47.5969|-120.6611|28
cody|44.5263|-109.0564|15
saint-pierre|14.7717|-61.1774|32
grand-case|18.1005|-63.0576|31
fajardo|18.3245|-65.6532|42
rincon|18.3397|-67.2507|42
harbour-island|25.4997|-76.6338|36
bimini|25.7033|-79.2733|36
marsh-harbour|26.5383|-77.061|36
kingston-jm|17.9712|-76.7928|24
port-antonio|18.1752|-76.4474|24
treasure-beach|17.8804|-77.7565|24
isabela|18.5008|-67.0237|42
jost-van-dyke|18.4468|-64.749|51
anegada|18.719|-64.3191|51
little-cayman|19.2802|-81.2841|11
cockburn-town|21.4713|-71.1474|18
shoal-bay-village|18.2533|-63.0304|2
little-bay-montserrat|16.8033|-62.2045|35
basse-terre|16.0001|-61.7333|20
les-saintes|15.8681|-61.5822|20
les-trois-ilets|14.5388|-61.0335|32
sainte-anne|14.4347|-60.8798|32
rodney-bay|14.0748|-60.9527|47
oistins|13.0632|-59.5422|6
holetown|13.1856|-59.6373|6
mustique|12.876|-61.1828|49
union-island|12.5972|-61.4335|49
carriacou|12.483|-61.4448|19
crown-point|11.1589|-60.8346|41
san-nicolas|12.4364|-69.909|4
westpunt|12.3808|-69.1626|14
rincon-bq|12.2387|-68.3298|27
st-georges-bda|32.381|-64.6767|53
caye-caulker|17.7432|-88.025|7
san-andres|12.5847|-81.7006|8
providencia|13.3489|-81.3742|8
bocas-del-toro|9.3432|-82.2428|38
glenwood-springs-colorado|39.5466|-107.3247|15
"""

    static let stateMainText = """
Alabama|Birmingham|33.5186|-86.8104|12
Alaska|Anchorage|61.2181|-149.9003|1
Arizona|Phoenix|33.4484|-112.0741|39
Arkansas|Little Rock|34.7465|-92.2896|12
California|Los Angeles|34.0522|-118.2437|28
Colorado|Denver|39.7392|-104.9903|15
Connecticut|Hartford|41.7658|-72.6734|37
Delaware|Wilmington|39.7391|-75.5398|37
Florida|Miami|25.7617|-80.1918|37
Georgia|Atlanta|33.749|-84.388|37
Hawaii|Honolulu|21.3069|-157.8583|54
Idaho|Boise|43.615|-116.2023|9
Illinois|Chicago|41.8781|-87.6298|12
Indiana|Indianapolis|39.7684|-86.1581|23
Iowa|Des Moines|41.5868|-93.625|12
Kansas|Overland Park|38.9822|-94.6708|12
Kentucky|Louisville|38.2527|-85.7585|26
Louisiana|New Orleans|29.9511|-90.0715|12
Maine|Portland|43.6591|-70.2568|37
Maryland|Baltimore|39.2904|-76.6122|37
Massachusetts|Boston|42.3601|-71.0589|37
Michigan|Detroit|42.3314|-83.0458|16
Minnesota|Minneapolis|44.9778|-93.265|12
Mississippi|Jackson|32.2988|-90.1848|12
Missouri|St. Louis|38.627|-90.1994|12
Montana|Bozeman|45.677|-111.0429|15
Nebraska|Omaha|41.2565|-95.9345|12
Nevada|Las Vegas|36.1699|-115.1398|28
New Hampshire|Manchester|42.9956|-71.4548|37
New Jersey|Newark|40.7357|-74.1724|37
New Mexico|Albuquerque|35.0844|-106.6504|15
New York|New York City|40.7128|-74.006|37
North Carolina|Charlotte|35.2271|-80.8431|37
North Dakota|Fargo|46.8772|-96.7898|12
Ohio|Cleveland|41.4993|-81.6944|37
Oklahoma|Oklahoma City|35.4676|-97.5164|12
Oregon|Portland|45.5152|-122.6784|28
Pennsylvania|Philadelphia|39.9526|-75.1652|37
Rhode Island|Providence|41.824|-71.4128|37
South Carolina|Charleston|32.7765|-79.9311|37
South Dakota|Sioux Falls|43.5446|-96.7311|12
Tennessee|Nashville|36.1627|-86.7816|12
Texas|Houston|29.7604|-95.3698|12
Utah|Salt Lake City|40.7608|-111.891|15
Vermont|Burlington|44.4759|-73.2121|37
Virginia|Richmond|37.5407|-77.436|37
Washington|Seattle|47.6062|-122.3321|28
West Virginia|Charleston|38.3498|-81.6326|37
Wisconsin|Milwaukee|43.0389|-87.9065|12
Wyoming|Jackson|43.4799|-110.7624|15
District of Columbia|Washington|38.9072|-77.0369|37
Washington DC|Washington|38.9072|-77.0369|37
Puerto Rico|San Juan|18.4655|-66.1057|42
"""

    static let storyCitiesText = """
illinois-chicago|Chicago|Illinois, United States|41.8756|-87.6244
evanston|Evanston|Illinois, United States|42.0694|-87.6829
alabama-birmingham|Birmingham|Alabama, United States|33.5207|-86.8024
alabama-huntsville|Huntsville|Alabama, United States|34.7298|-86.5859
alabama-mobile|Mobile|Alabama, United States|30.6913|-88.0438
phoenix|Phoenix|Arizona, United States|33.4484|-112.0741
scottsdale|Scottsdale|Arizona, United States|33.4942|-111.926
sedona|Sedona|Arizona, United States|34.8689|-111.7614
flagstaff|Flagstaff|Arizona, United States|35.1988|-111.6518
page|Page|Arizona, United States|36.9148|-111.4573
tucson|Tucson|Arizona, United States|32.2229|-110.9748
casa-grande|Casa Grande|Arizona, United States|32.8773|-111.7537
little-rock|Little Rock|Arkansas, United States|34.7465|-92.2896
fayetteville|Fayetteville|Arkansas, United States|36.0626|-94.1574
los-angeles|Los Angeles|California, United States|34.0537|-118.2428
san-francisco|San Francisco|California, United States|37.7879|-122.4075
palm-springs|Palm Springs|California, United States|33.8246|-116.5403
san-diego|San Diego|California, United States|32.7157|-117.1638
santa-barbara|Santa Barbara|California, United States|34.4221|-119.7027
yosemite|Yosemite|California, United States|37.8393|-119.5165
lake-tahoe|Lake Tahoe|California, United States|39.0885|-120.0504
denver|Denver|Colorado, United States|39.7392|-104.9849
aspen|Aspen|Colorado, United States|39.1911|-106.8236
boulder|Boulder|Colorado, United States|40.015|-105.2705
colorado-springs|Colorado Springs|Colorado, United States|38.834|-104.8253
vail|Vail|Colorado, United States|39.6438|-106.3888
wilmington|Wilmington|Delaware, United States|39.7383|-75.5527
rehoboth-beach|Rehoboth Beach|Delaware, United States|38.7165|-75.0835
hartford|Hartford|Connecticut, United States|41.7662|-72.6733
new-haven|New Haven|Connecticut, United States|41.3082|-72.9251
stamford|Stamford|Connecticut, United States|41.0534|-73.5387
miami|Miami|Florida, United States|25.7742|-80.1936
orlando|Orlando|Florida, United States|28.5421|-81.379
tampa|Tampa|Florida, United States|27.945|-82.4583
key-west|Key West|Florida, United States|24.5548|-81.8021
fort-lauderdale|Fort Lauderdale|Florida, United States|26.1223|-80.1434
boca-raton|Boca Raton|Florida, United States|26.3587|-80.0831
atlanta|Atlanta|Georgia, United States|33.7545|-84.3898
savannah|Savannah|Georgia, United States|32.079|-81.0921
honolulu|Honolulu|Hawaii, United States|21.3045|-157.8557
maui|Maui|Hawaii, United States|20.803|-156.3107
kauai|Kauai|Hawaii, United States|22.0504|-159.5589
big-island|Big Island|Hawaii, United States|19.5896|-155.4487
boise|Boise|Idaho, United States|43.6166|-116.2009
sun-valley|Sun Valley|Idaho, United States|43.6962|-114.3531
coeur-dalene|Coeur d'Alene|Idaho, United States|47.6743|-116.7812
indianapolis|Indianapolis|Indiana, United States|39.7683|-86.1584
south-bend|South Bend|Indiana, United States|41.6834|-86.25
bloomington|Bloomington|Indiana, United States|39.167|-86.5343
des-moines|Des Moines|Iowa, United States|41.5869|-93.6249
iowa-city|Iowa City|Iowa, United States|41.6613|-91.5299
overland-park|Overland Park|Kansas, United States|38.9743|-94.6852
wichita|Wichita|Kansas, United States|37.6922|-97.3375
louisville|Louisville|Kentucky, United States|38.2542|-85.7594
lexington|Lexington|Kentucky, United States|38.0464|-84.497
new-orleans|New Orleans|Louisiana, United States|29.9575|-90.0629
baton-rouge|Baton Rouge|Louisiana, United States|30.4494|-91.187
portland-me|Portland|Oregon, United States|45.5202|-122.6742
bar-harbor|Bar Harbor|Maine, United States|44.3876|-68.2043
baltimore|Baltimore|Maryland, United States|39.2909|-76.6108
annapolis|Annapolis|Maryland, United States|38.9786|-76.4928
ocean-city|Ocean City|Maryland, United States|38.3315|-75.0874
boston|Boston|Massachusetts, United States|42.3588|-71.0578
cape-cod|Cape Cod|Massachusetts, United States|41.7988|-69.9961
detroit|Detroit|Michigan, United States|42.3316|-83.0466
ann-arbor|Ann Arbor|Michigan, United States|42.2814|-83.7485
traverse-city|Traverse City|Michigan, United States|44.7606|-85.6166
minneapolis|Minneapolis|Minnesota, United States|44.9773|-93.2655
duluth|Duluth|Minnesota, United States|46.7838|-92.1053
jackson|Jackson|Mississippi, United States|32.2999|-90.183
biloxi|Biloxi|Mississippi, United States|30.4008|-88.8894
st-louis|St. Louis|Missouri, United States|38.6254|-90.19
kansas-city|Kansas City|Missouri, United States|39.1001|-94.5781
branson|Branson|Missouri, United States|36.6441|-93.2169
bozeman|Bozeman|Montana, United States|45.6794|-111.044
kalispell|Kalispell|Montana, United States|48.2022|-114.3153
omaha|Omaha|Nebraska, United States|41.2587|-95.9384
lincoln|Lincoln|Nebraska, United States|40.8089|-96.7078
las-vegas|Las Vegas|Nevada, United States|36.1674|-115.1484
reno|Reno|Nevada, United States|39.5262|-119.8127
manchester|Manchester|New Hampshire, United States|42.9956|-71.4548
portsmouth|Portsmouth|New Hampshire, United States|43.0751|-70.7602
teaneck|Teaneck|New Jersey, United States|40.886|-74.0073
lakewood|Lakewood|New Jersey, United States|40.0941|-74.215
passaic|Passaic|New Jersey, United States||
atlantic-city|Atlantic City|New Jersey, United States|39.3643|-74.4229
albuquerque|Albuquerque|New Mexico, United States|35.0841|-106.651
santa-fe|Santa Fe|New Mexico, United States|35.6876|-105.9385
new-york-city|New York City|New York, United States|40.7127|-74.006
brooklyn|Brooklyn|New York, United States|40.6526|-73.9497
catskills|Catskills|New York, United States|42.028|-74.2698
monsey|Monsey|New York, United States|41.118|-74.0594
niagara-falls|Niagara Falls|New York, United States|43.0848|-79.0702
rochester|Rochester|New York, United States|43.1573|-77.6152
the-hamptons|The Hamptons|New York, United States|40.9543|-72.1983
charlotte|Charlotte|North Carolina, United States|35.2272|-80.8431
raleigh|Raleigh|North Carolina, United States|35.7804|-78.6391
asheville|Asheville|North Carolina, United States|35.5954|-82.5508
outer-banks|Outer Banks|North Carolina, United States|35.5669|-75.4688
fargo|Fargo|North Dakota, United States|46.8772|-96.7898
bismarck|Bismarck|North Dakota, United States|46.8083|-100.7837
cleveland|Cleveland|Ohio, United States|41.4997|-81.6937
columbus|Columbus|Ohio, United States|39.9623|-83.0007
cincinnati|Cincinnati|Ohio, United States|39.1013|-84.5127
oklahoma-city|Oklahoma City|Oklahoma, United States|35.473|-97.5171
tulsa|Tulsa|Oklahoma, United States|36.1563|-95.9928
bend|Bend|Oregon, United States|44.0582|-121.3153
philadelphia|Philadelphia|Pennsylvania, United States|39.9527|-75.1635
pittsburgh|Pittsburgh|Pennsylvania, United States|40.4407|-80.0026
poconos|Poconos|Pennsylvania, United States|41.0256|-75.6046
providence|Providence|Rhode Island, United States|41.824|-71.4128
newport|Newport|Rhode Island, United States|41.49|-71.3138
charleston|Charleston|South Carolina, United States|32.7884|-79.9399
myrtle-beach|Myrtle Beach|South Carolina, United States|33.6956|-78.89
hilton-head|Hilton Head|South Carolina, United States|32.1618|-80.7513
sioux-falls|Sioux Falls|South Dakota, United States|43.5476|-96.7294
rapid-city|Rapid City|South Dakota, United States|44.0806|-103.228
nashville|Nashville|Tennessee, United States|36.1623|-86.7743
memphis|Memphis|Tennessee, United States|35.146|-90.0518
gatlinburg|Gatlinburg|Tennessee, United States|35.7143|-83.5102
houston|Houston|Texas, United States|29.7589|-95.3677
austin|Austin|Texas, United States|30.2649|-97.7474
dallas|Dallas|Texas, United States|32.7763|-96.7969
san-antonio|San Antonio|Texas, United States|29.4246|-98.4951
salt-lake-city|Salt Lake City|Utah, United States|40.7596|-111.8868
park-city|Park City|Utah, United States|40.6461|-111.498
moab|Moab|Utah, United States|38.5738|-109.5462
zion-national-park|Zion National Park|Utah, United States|37.3222|-113.0048
burlington|Burlington|Vermont, United States|44.4762|-73.2129
stowe|Stowe|Vermont, United States|44.4644|-72.6856
richmond|Richmond|Virginia, United States|37.5385|-77.4343
virginia-beach|Virginia Beach|Virginia, United States|36.8497|-75.9761
williamsburg|Williamsburg|Virginia, United States|37.2712|-76.7
seattle|Seattle|Washington, United States|47.6038|-122.3301
spokane|Spokane|Washington, United States|47.6572|-117.4235
charleston-wv|Charleston WV|West Virginia, United States|38.3506|-81.6333
harpers-ferry|Harpers Ferry|West Virginia, United States|39.3234|-77.732
milwaukee|Milwaukee|Wisconsin, United States|43.0386|-87.9091
madison|Madison|Wisconsin, United States|43.0747|-89.3842
wisconsin-dells|Wisconsin Dells|Wisconsin, United States|43.6256|-89.7716
jackson-hole|Jackson Hole|Wyoming, United States|43.6088|-110.738
yellowstone|Yellowstone|Wyoming, United States|44.6201|-110.5607
anchorage|Anchorage|Alaska, United States|61.2163|-149.8949
juneau|Juneau|Alaska, United States|58.302|-134.4197
fairbanks|Fairbanks|Alaska, United States|64.8378|-147.7167
seward|Seward|Alaska, United States|60.1014|-149.4404
girdwood|Girdwood|Alaska, United States|60.9632|-149.1337
talkeetna|Talkeetna|Alaska, United States|62.2676|-150.0295
denali-national-park|Denali National Park|Alaska, United States|63.7302|-148.8921
homer|Homer|Alaska, United States|59.6454|-151.5446
whittier|Whittier|Alaska, United States|60.7731|-148.6839
valdez|Valdez|Alaska, United States|61.1299|-146.3494
ketchikan|Ketchikan|Alaska, United States|55.3431|-131.6467
skagway|Skagway|Alaska, United States|59.6226|-135.4094
sitka|Sitka|Alaska, United States|57.4086|-135.4596
dc-washington|Washington|Washington DC, United States|38.8898|-77.0403
ocho-rios|Ocho Rios|Saint Ann, Jamaica|18.4081|-77.1011
jerusalem|Jerusalem|Israel|31.7788|35.2258
san-jose|San José|Costa Rica|9.9327|-84.0797
manuel-antonio|Manuel Antonio|Costa Rica|9.4086|-84.1548
la-fortuna|La Fortuna|Costa Rica|10.4717|-84.6444
tamarindo|Tamarindo|Guanacaste, Costa Rica|10.2984|-85.84
monteverde|Monteverde|Costa Rica|10.2912|-84.8136
cape-town|Cape Town|South Africa|-33.9288|18.4172
nassau|Nassau|Bahamas|25.0782|-77.3383
san-juan|San Juan|Puerto Rico|18.3842|-66.0534
vieques-island|Vieques Island|Puerto Rico|18.1217|-65.4571
dorado-beach|Dorado Beach|Puerto Rico|18.4731|-66.2827
palm-beach|Palm Beach|Aruba|12.5704|-70.0394
oranjestad|Oranjestad|Oranjestad, Aruba|12.5337|-70.0548
eagle-beach|Eagle Beach|Aruba|12.5466|-70.0599
simpson-bay|Simpson Bay|Saint Martin|18.0397|-63.0972
bridgetown|Bridgetown|Barbados|13.0978|-59.6184
st-thomas|St. Thomas|US Virgin Islands|18.3429|-64.9189
charlotte-amalie|Charlotte Amalie|Thomas, US Virgin Islands|18.3369|-64.9622
st-john-usvi|St. John|John, US Virgin Islands|18.3356|-64.755
cruz-bay|Cruz Bay|John, US Virgin Islands|18.3308|-64.7945
st-croix-usvi|St. Croix|Croix, US Virgin Islands|17.7291|-64.7589
christiansted|Christiansted|Croix, US Virgin Islands|17.7439|-64.708
red-hook|Red Hook|Thomas, US Virgin Islands|18.3261|-64.8518
george-town|George Town|Georgetown, Cayman Islands|19.2923|-81.3795
punta-cana|Punta Cana|Dominican Republic|18.5566|-68.3692
castries|Castries|Saint Lucia|14.0096|-60.9902
guatemala-city|Guatemala City|Guatemala|14.6416|-90.5133
providenciales|Providenciales|Turks and Caicos|21.8028|-72.1603
willemstad|Willemstad|Curacao|12.1067|-68.9351
panama-city|Panama City|Panama|8.9714|-79.5342
gustavia|Gustavia|Saint Barthélemy|17.8957|-62.8508
st-jean-sbh|St. Jean|Barts, Saint Barthélemy|17.9015|-62.8371
san-pedro|San Pedro|Belize|17.9204|-87.9622
the-valley|The Valley|Anguilla|18.2146|-63.0518
cancun|Cancun|Quintana Roo, Mexico|21.1527|-86.8426
cozumel|Cozumel|Quintana Roo, Mexico|20.4321|-86.9207
playa-del-carmen|Playa del Carmen|Quintana Roo, Mexico|20.6463|-87.0808
tulum|Tulum|Quintana Roo, Mexico|20.4296|-87.6529
cabo-san-lucas|Cabo San Lucas|Baja California Sur, Mexico|22.8939|-109.9201
mexico-city|Mexico City|Distrito Federal, Mexico|19.4326|-99.1332
isla-mujeres|Isla Mujeres|Quintana Roo, Mexico|21.2372|-86.735
isla-navidad|Isla Navidad|Colima, Mexico|19.1796|-104.678
antigua-guatemala|Antigua Guatemala|Sacatepéquez, Guatemala|14.5568|-90.7337
roatan|Roatan|Bay Islands, Honduras|16.349|-86.4978
san-juan-del-sur|San Juan del Sur|Rivas, Nicaragua|11.1944|-85.8598
exuma|Exuma|Exuma District, Bahamas|23.9685|-76.1799
eleuthera|Eleuthera|Eleuthera District, Bahamas|25.0885|-76.1346
freeport|Freeport|Grand Bahama, Bahamas|26.5943|-78.5529
st-johns|St. John's|Antigua, Antigua and Barbuda|17.1185|-61.8449
english-harbour|English Harbour|Antigua, Antigua and Barbuda|17.0089|-61.7636
barbuda|Barbuda|Barbuda, Antigua and Barbuda|17.6219|-61.784
hamilton-bermuda|Hamilton|Pembroke Parish, Bermuda|32.3022|-64.7741
kralendijk|Kralendijk|Bonaire, Bonaire|12.1473|-68.274
road-town|Road Town|Tortola, British Virgin Islands|18.4258|-64.6231
havana|Havana|La Habana, Cuba|23.1353|-82.359
roseau|Roseau|Saint George, Dominica|15.2992|-61.3873
san-salvador|San Salvador|San Salvador Department, El Salvador|-26.2282|-57.1818
st-georges-grenada|St. George's|Saint George, Grenada|12.0535|-61.7518
pointe-a-pitre|Pointe-à-Pitre|Grande-Terre, Guadeloupe|16.2409|-61.5334
port-au-prince|Port-au-Prince|Ouest Department, Haiti|18.5473|-72.3396
tegucigalpa|Tegucigalpa|Francisco Morazán, Honduras|14.1058|-87.2047
fort-de-france|Fort-de-France|Martinique, Martinique|14.6028|-61.0677
brades|Brades|Saint Peter, Montserrat|16.7899|-62.2099
little-corn-island|Little Corn Island|Atlántico Sur, Nicaragua|12.2885|-82.9829
managua|Managua|Managua Department, Nicaragua|12.1547|-86.2737
the-bottom|The Bottom|The Bottom, Saba|17.6323|-63.2357
basseterre|Basseterre|Saint George Basseterre, Saint Kitts and Nevis|17.2961|-62.7223
kingstown|Kingstown|Saint George Parish, Saint Vincent and the Grenadines|13.1562|-61.228
oranjestad-statia|Oranjestad|Oranjestad, Sint Eustatius|17.4953|-62.9794
port-of-spain|Port of Spain|Trinidad, Trinidad and Tobago|10.6573|-61.518
san-blas|San Blas Islands|Yala, Panama|9.5859|-78.8788
santo-domingo|Santo Domingo|Nacional, Dominican Republic|18.4714|-69.8918
philipsburg|Philipsburg|Philipsburg, Saint Martin|18.0251|-63.0483
yosemite|Yosemite National Park|California, United States|37.8393|-119.5165
grand-canyon|Grand Canyon Village|Az, United States|36.0578|-112.1282
carmel|Carmel-by-the-Sea|California, United States|36.5553|-121.9233
san-juan-islands|San Juan Islands|Wa, United States|48.5371|-123.0907
springdale|Springdale (Zion NP)|Ut, United States|37.1889|-112.9986
moab|Moab (Arches NP)|Ut, United States|38.5738|-109.5462
key-largo|Key Largo|Florida, United States|25.1093|-80.424
st-augustine|St. Augustine|Florida, United States|29.8947|-81.3145
telluride|Telluride|Colorado, United States|37.9375|-107.8123
nantucket|Nantucket|Ma, United States|41.2844|-70.0984
whitefish|Whitefish (Glacier NP)|Mt, United States|48.4108|-114.3346
lake-placid|Lake Placid|New York, United States|44.2831|-73.9828
gulf-shores|Gulf Shores|Al, United States|30.2711|-87.6894
hot-springs|Hot Springs|Ar, United States|34.5038|-93.0552
eureka-springs|Eureka Springs|Ar, United States|36.4001|-93.7392
monterey|Monterey|California, United States|36.2231|-121.3877
napa-valley|Napa Valley|California, United States|38.4617|-122.3142
big-sur|Big Sur|California, United States|36.1437|-121.5646
joshua-tree|Joshua Tree|California, United States|34.1234|-116.3129
rocky-mountain-np|Rocky Mountain National Park|Colorado, United States|40.3554|-105.7177
mystic|Mystic|Ct, United States|41.356|-71.9573
naples|Naples|Florida, United States|26.1422|-81.7943
galena|Galena|Il, United States|42.4157|-90.4295
salem-ma|Salem|Ma, United States|42.5214|-70.8957
yellowstone-west|West Yellowstone|Mt, United States|44.6632|-111.1012
cape-may|Cape May|New Jersey, United States|39.1765|-74.8012
cannon-beach|Cannon Beach|Or, United States|45.89|-123.9619
hilton-head|Hilton Head Island|Sc, United States|32.1618|-80.7513
badlands-np|Badlands National Park|Sd, United States|43.5271|-102.3617
great-smoky-mtns|Great Smoky Mountains|Tn, United States|35.6342|-83.4024
olympic-np|Olympic National Park|Wa, United States|47.7865|-123.5361
new-river-gorge|New River Gorge|Wv, United States|37.8967|-81.043
door-county|Door County|Wi, United States|44.7616|-87.533
yellowstone-wy|Yellowstone National Park|Wy, United States|44.6201|-110.5607
destin|Destin|Florida, United States|30.3935|-86.4958
chattanooga|Chattanooga|Tn, United States|35.0457|-85.3095
taos|Taos|Nm, United States|36.4072|-105.5733
montego-bay|Montego Bay|James, Jamaica|18.4725|-77.9217
negril|Negril|Westmoreland, Jamaica|18.278|-78.3495
virgin-gorda|Virgin Gorda|Gorda, British Virgin Islands|18.4654|-64.4155
ponce|Ponce|Ponce, Puerto Rico|18.0116|-66.614
culebra|Culebra|Culebra, Puerto Rico|18.3031|-65.3001
nevis|Nevis|Nevis, Saint Kitts and Nevis|17.1509|-62.5853
bequia|Bequia|Grenadines, Saint Vincent and the Grenadines|13.0165|-61.232
marigot|Marigot|Martin, Saint Martin|18.0669|-63.0849
soufriere|Soufrière|Soufriere, Saint Lucia|13.8541|-61.0586
bentonville|Bentonville|Ar, United States|36.3729|-94.2088
santa-cruz|Santa Cruz|California, United States|37.0501|-121.9906
death-valley|Death Valley|California, United States|36.4229|-116.9137
sequoia-np|Sequoia National Park|California, United States|36.4958|-118.5599
breckenridge|Breckenridge|Colorado, United States|39.4829|-106.0465
sarasota|Sarasota|Florida, United States|27.3366|-82.5309
clearwater|Clearwater|Florida, United States|27.9659|-82.8001
jekyll-island|Jekyll Island|Ga, United States|31.0656|-81.414
hilo|Hilo|Hi, United States|19.7074|-155.0816
lawrence|Lawrence|Ks, United States|38.9719|-95.2359
camden-me|Camden|Me, United States|44.2155|-69.0852
cambridge-ma|Cambridge|Ma, United States|42.3656|-71.104
provincetown|Provincetown|Ma, United States|42.0526|-70.1859
mackinac-island|Mackinac Island|Mi, United States|45.8658|-84.6305
natchez|Natchez|Ms, United States|31.5604|-91.4032
glacier-np|Glacier National Park|Mt, United States|48.6175|-113.7609
boulder-city|Boulder City|Nv, United States|35.9788|-114.8338
north-conway|North Conway|Nh, United States|44.0378|-71.1238
princeton|Princeton|New Jersey, United States|40.3497|-74.6597
carlsbad-nm|Carlsbad|Nm, United States|32.4257|-104.2376
lake-george|Lake George|New York, United States|43.426|-73.7124
boone|Boone|Nc, United States|36.2188|-81.684
astoria|Astoria|Or, United States|46.1882|-123.832
hershey|Hershey|Pa, United States|40.285|-76.6535
lancaster-pa|Lancaster|Pa, United States|40.038|-76.3057
block-island|Block Island|Ri, United States|41.1896|-71.5679
greenville-sc|Greenville|Sc, United States|34.8514|-82.3985
fort-worth|Fort Worth|Tx, United States|32.7532|-97.3327
fredericksburg|Fredericksburg|Tx, United States|30.2752|-98.872
bryce-canyon|Bryce Canyon National Park|Ut, United States|37.5708|-112.1856
charlottesville|Charlottesville|Va, United States|38.0293|-78.4767
leavenworth|Leavenworth|Wa, United States|47.5969|-120.6611
cody|Cody|Wy, United States|44.5263|-109.0564
saint-pierre|Saint-Pierre|Pierre, Martinique|14.7717|-61.1774
grand-case|Grand Case|Martin, Saint Martin|18.1005|-63.0576
fajardo|Fajardo|Fajardo, Puerto Rico|18.3245|-65.6532
rincon|Rincón|Rincon, Puerto Rico|18.3397|-67.2507
harbour-island|Harbour Island|Eleuthera, Bahamas|25.4997|-76.6338
bimini|Bimini|Bimini, Bahamas|25.7033|-79.2733
marsh-harbour|Marsh Harbour (Abaco)|Abaco, Bahamas|26.5383|-77.061
kingston-jm|Kingston|Surrey, Jamaica|17.9712|-76.7928
port-antonio|Port Antonio|Portland, Jamaica|18.1752|-76.4474
treasure-beach|Treasure Beach|Elizabeth, Jamaica|17.8804|-77.7565
isabela|Isabela|Isabela, Puerto Rico|18.5008|-67.0237
jost-van-dyke|Jost Van Dyke|Dyke, British Virgin Islands|18.4468|-64.749
anegada|Anegada|Anegada, British Virgin Islands|18.719|-64.3191
little-cayman|Little Cayman|Cayman, Cayman Islands|19.2802|-81.2841
cockburn-town|Cockburn Town (Grand Turk)|Turk, Turks and Caicos|21.4713|-71.1474
shoal-bay-village|Shoal Bay Village|Anguilla, Anguilla|18.2533|-63.0304
little-bay-montserrat|Little Bay|Little Bay, Montserrat|16.8033|-62.2045
basse-terre|Basse-Terre|Terre, Guadeloupe|16.0001|-61.7333
les-saintes|Terre-de-Haut (Les Saintes)|Saintes, Guadeloupe|15.8681|-61.5822
les-trois-ilets|Les Trois-Îlets|Martinique, Martinique|14.5388|-61.0335
sainte-anne|Sainte-Anne|Martinique, Martinique|14.4347|-60.8798
rodney-bay|Rodney Bay|Islet, Saint Lucia|14.0748|-60.9527
oistins|Oistins|Church, Barbados|13.0632|-59.5422
holetown|Holetown|James, Barbados|13.1856|-59.6373
mustique|Mustique|Grenadines, Saint Vincent and the Grenadines|12.876|-61.1828
union-island|Union Island|Grenadines, Saint Vincent and the Grenadines|12.5972|-61.4335
carriacou|Carriacou|Carriacou, Grenada|12.483|-61.4448
crown-point|Crown Point|Tobago, Trinidad and Tobago|11.1589|-60.8346
san-nicolas|San Nicolas|Aruba, Aruba|12.4364|-69.909
westpunt|Westpunt|Curacao, Curacao|12.3808|-69.1626
rincon-bq|Rincon|Bonaire, Bonaire|12.2387|-68.3298
st-georges-bda|St. George's|Bermuda, Bermuda|32.381|-64.6767
caye-caulker|Caye Caulker|District, Belize|17.7432|-88.025
san-andres|San Andrés|Andres, United States|12.5847|-81.7006
providencia|Providencia|Andres, United States|13.3489|-81.3742
bocas-del-toro|Bocas Town|Toro, Panama|9.3432|-82.2428
glenwood-springs-colorado|Glenwood Springs|Colorado, United States|39.5466|-107.3247
"""
}
