<p align="center"><img src="./DiaBLE/Assets.xcassets/AppIcon.appiconset/Icon.png" width="25%" /> &nbsp; &nbsp; <img src="https://github.com/gui-dos/DiaBLE/assets/7220550/901ad341-edfb-426e-9617-6763cf377447" width="20.5%"/> &nbsp; &nbsp; <img src="https://github.com/gui-dos/DiaBLE/assets/7220550/4d84f138-5b31-4db3-a407-f85265a78e66" width="20.5%" /></p>
<br><br>

**ChangeLog:**
* 20/1/2024 - [Build 88](https://github.com/gui-dos/DiaBLE/commit/d1333f3)  
  - Shell: import and dump LibreView CSV files by using TabularData:
<p align="center"><img src="https://github.com/gui-dos/DiaBLE/assets/7220550/01050cf3-2f75-4034-8861-5e33475c972b" width="75%"/>
<br><br>

## Builds

To build the project you have to duplicate the file _DiaBLE.xcconfig_, rename the copy to ***DiaBLEOverride.xcconfig*** (the missing reference displayed by Xcode in red should then point to it) and edit it by deleting the trailing lines after `// Remove the following...` and replacing `##TEAM_ID##` with your Apple Team ID so that the first line should read for example `DEVELOPMENT_TEAM = Z25SC9UDC8`.

The NFC capabilities require a paid Apple Developer Program **annual membership**. If you won't [request](https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/) a *Critical Alert Notifications Entitlement* you have to edit out the lines `<key>com.apple.developer.usernotifications.critical-alerts</key>` `<true/>` from the _.entitlements_ files in the folders _DiaBLE_ and _DiaBLE Watch_.

A public beta of DiaBLE is availaBLE at **[TestFlight](https://testflight.apple.com/join/H48doU3l)**: I'll periodically expunge anonymous users I didn't invite or who didn't sponsor me through PayPal $-). If you own an iPad you can download the [zipped archive](https://github.com/gui-dos/DiaBLE/archive/refs/heads/main.zip) of this repository and just tap _DiaBLE Playground.swiftpm_ to test the corresponding features and even more past legacy ones.

Currently I am targeting only the **latest betas of Xcode 16 and iOS 18** and focusing on the new **Libre 3** and **Dexcom G7**. Please refer to the [**TODOs**](https://github.com/gui-dos/DiaBLE/blob/main/TODO.md) list for the up-to-date status of all the current limitations and known bugs of this **prototype**.

## Warnings

  * the temperature-based calibration algorithm has been derived from the old LibreLink 2.3: it is known that the Vendor improves its algorithms at every new release, smoothing the historical values and projecting the trend ones into the future to compensate the interstitial delay but these further stages aren't understood yet; I never was convinced by the simple linear regression models that others apply on finger pricks;
  * activating the BLE streaming of data on a Libre 2 will break other apps' pairings and you will have to reinstall them to get their alarms back again; in Test mode it is possiBLE however to sniff the incoming data of multiple apps running side-by-side by just activating the notifications on the known BLE characteristics: the same technique is used to analyze the Libre 3 incoming traffic since the Core Bluetooth connections are reference-counted;
  * connecting directly to a Libre 2/3 from an Apple Watch is currently just a proof of concept that it is technically possiBLE: keeping the connection in the background will require additional work and AFAIK nobody else is capaBLE of doing the job... :-P
  
The Shell in the Console allows opening both encrypted and decrypted _trident.realm_ files from a backup of the Libre 3 app data (the Container folder extracted for example by using iMazing): see the nice technical post (mentioning me 😎) ["Liberating glucose data from the Freestyle Libre 3"](https://frdmtoplay.com/freeing-glucose-data-from-the-freestyle-libre-3/) (a rooted Android Virtual Machine like Waydroid or the default _Google APIs System Image_ in Android Studio is required to unwrap the Realm encryption key).

---
***Credits***: [@bubbledevteam](https://github.com/bubbledevteam), [@captainbeeheart](https://github.com/captainbeeheart), [@creepymonster](https://github.com/creepymonster), [@cryptax](https://github.com/cryptax), [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift), [@dabear](https://github.com/dabear), [@DecentWoodpecker67](https://github.com/DecentWoodpecker67), [Glucosy](https://github.com/TopScrech/Glucosy), [@ivalkou](https://github.com/ivalkou), [Jaap Korthals Altes](https://github.com/j-kaltes), [@keencave](https://github.com/keencave), [LibreMonitor](https://github.com/UPetersen/LibreMonitor/tree/Swift4), [LibreWrist]( https://github.com/poml88/LibreWrist), [Loop](https://github.com/LoopKit/Loop), [Marek Macner](https://github.com/MarekM60), [@monder](https://github.com/monder), [Nightguard]( https://github.com/nightscout/nightguard), [Nightscout LibreLink Up Uploader](https://github.com/timoschlueter/nightscout-librelink-up), [@travisgoodspeed](https://github.com/travisgoodspeed), [WoofWoof](https://github.com/gshaviv/ninety-two), [xDrip](https://github.com/Faifly/xDrip), [xDrip+](https://github.com/NightscoutFoundation/xDrip), [xDrip4iO5](https://github.com/JohanDegraeve/xdripswift).

###### ***Disclaimer: the decrypting keys I am publishing are not related to user accounts and can be dumped from the sensor memory by using DiaBLE itself. The online servers I am using probably are tracking your personal data but all the traffic sent/received by DiaBLE is clearly shown in its logs. The reverse-engineered code I am copying&pasting has been retrieved from other GitHub repos or reproduced simply by using open-source tools like Ghidra and `jadx-gui`.***
