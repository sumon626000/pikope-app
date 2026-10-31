PikoPe marketing landing (ARCHIVED BACKUP)
==========================================

This folder is a backup of the old Play Store-style static site.
It is NOT deployed on the main domain anymore.

MAIN DOMAIN (pikope.com)
  → Flutter web app from pikope-web/ (see pikope-web/DEPLOY.txt)
  → Document root: upload build/web (or deploy zip) to public_html/

API + admin
  → https://adminnew.pikope.com (backend/)

To restore this landing later (subdomain or separate path):
  Upload index.html + assets/ to a folder, e.g. pikope.com/old/ or landing.pikope.com
  Still uses API: /landing/public and Admin → Landing page for APK/copy.

See DEPLOY.txt in this folder for the original Hostinger steps.
