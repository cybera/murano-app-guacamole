all: zip import

zip:
	rm ca.cybera.Guacamole.zip || true
	zip -r ca.cybera.Guacamole.zip *

import:
	murano package-import --is-public --exists-action u ca.cybera.Guacamole.zip
