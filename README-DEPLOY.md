# Updating the app on GitHub

**Version in this file: 2026.10.29-1**

## Replace the old file
1. Open your GitHub repository and go to the folder that holds the current `index.html`.
2. Choose **Add file → Upload files**, drag the new `index.html` in (same name, same folder) and **Commit changes**.
3. Netlify (or GitHub Pages) publishes it by itself, usually within a minute or two.

The new file replaces the old one because it has the same name and location. Nothing else needs to change.

## What teachers see
- Anyone with the app open, or opening it later, gets a message: **"A newer version of the app is available. Your records are saved on this device and will not be lost."** with **Reload now**.
- You can check by hand: left menu, bottom, **Check for updates**.
- After the update the app confirms **"Updated to version …"** once.

## Your records are safe
Records are kept in each browser for the website address, not in `index.html`, so replacing the file does not touch them. Keep using the **same website address**. If the address ever changes, first make a backup in **Settings** and restore it at the new address.

## Good to know
- Each new build has a new version number inside the file. If you upload a file with the same version as the one already live, devices will not show the update message.
- `netlify.toml` is optional: it only tells browsers to always look for the newest `index.html`.
- `share-link-setup.sql` is needed only once, for attendance share links. It does not change.
- The file is large (about 3.7 MB) because your DepEd workbook and the PDF reader are built in. That is normal.
- Certificate and poster fonts (Great Vibes, Oswald, Montserrat, Cinzel) load from Google Fonts when the device is online. Offline, the device's own fonts are used. For the exact script style everywhere, upload a font file under **Top Students & Certificates → School and certificate settings**.
