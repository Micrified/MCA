
import archive_core

tag = archive_core.run(silent=True, very_silent=True, actually_archive=False)

print(tag['tag'])
