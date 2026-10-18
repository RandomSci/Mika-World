"""Publishing: the YouTube side of the stream (pre-live metadata, the autopilot, clips).

This package owns the YouTube credentials, reads them from the environment of
the server process only and never logs them.
"""

from .service import PublicationService  # noqa: F401
from .settings import PublishSettings  # noqa: F401
