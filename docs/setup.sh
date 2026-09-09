# TODO: incorporate these as instructions in the intro doc

# start jaeger
docker run -d --name jaeger -p 16686:16686 -p 4317:4317 jaegertracing/all-in-one:latest

# git clone trendwatch
pushd trendwatch
# python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
popd

