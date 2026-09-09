
TODO: incorporate the below into the instructions proper so no setup remains

# Start the stub IdP in the background
# same process mints the JWTs and serves JWKS
python3 fake_idp.py >/tmp/fake_idp.log 2>&1 &

# challenge terminal gets $READER_JWT and $PUBLISHER_JWT.
source /root/trendwatch/fake_idp.env
