FROM elixir:1.18.4-otp-27@sha256:a89eddfaaca9abc52bbc9025fc5220e23b082e7e2cacc8baaf5f39afb9b36941
ENV MIX_HOME=/opt/mix HEX_HOME=/opt/hex HOME=/tmp
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs pins.exs .formatter.exs ./
COPY locks locks
COPY config config
RUN PROJECTION_VARIANT=before mix deps.get && PROJECTION_VARIANT=after mix deps.get
RUN PROJECTION_VARIANT=before mix deps.compile && PROJECTION_VARIANT=after mix deps.compile
COPY lib lib
RUN PROJECTION_VARIANT=before mix compile --warnings-as-errors
RUN PROJECTION_VARIANT=after mix compile --warnings-as-errors
COPY scripts scripts
RUN rm -rf /tmp/mix_*
ENV BENCH_PRECOMPILED=1
CMD ["bash", "scripts/benchmark.sh"]
