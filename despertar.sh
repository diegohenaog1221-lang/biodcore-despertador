#!/usr/bin/env bash
#
# Mantiene caliente el proyecto de Supabase de BIODCORE: pingea la
# AUTENTICACION y la BASE DE DATOS cada INTERVALO segundos durante
# DURACION_MIN minutos, y termina.
#
# ─────────────────────────────────────────────────────────────────────────────
# POR QUE UN BUCLE Y NO UN PING SUELTO
# ─────────────────────────────────────────────────────────────────────────────
#
# Este trabajo declara `cron: */5`, que son 288 ejecuciones al dia. GitHub no
# las dispara: en los repositorios publicos el evento `schedule` es de mejor
# esfuerzo y se descarta bajo carga. Medido el 1 de noviembre de 2026 sobre
# las 61 ejecuciones de los once dias anteriores:
#
#   ejecuciones al dia .............. 5,7      (deberian ser 288)
#   hueco mediano ................... 254 min  (4 h 14)
#   hueco maximo .................... 428 min  (7 h 08)
#   huecos de mas de 25 minutos ..... 60 de 60
#   conclusiones .................... 61 en VERDE
#
# Y ahi esta la trampa: NO FALLA NINGUNA. El ping sale verde todas las veces
# mientras la base se pasa el dia congelandose. Es la misma clase de engaño
# que la version que solo consultaba /auth/v1/health, y se descubre igual:
# midiendo, no mirando.
#
# Veinticinco minutos de reposo bastan para volver a enfriarse, asi que con
# huecos de cuatro horas la base estaba FRIA EL 90,3% DEL TIEMPO (232,5 h de
# las 257 medidas).
#
# No se arregla bajando el intervalo ni añadiendo avisos: lo que falla es el
# disparador. Asi que cada ejecucion deja de durar diez segundos y pasa a
# pingear durante horas. Con eso, lo que GitHub tiene que acertar no es
# "disparar cada cinco minutos" sino "disparar una vez cada varias horas",
# que es justo lo que si hace.
#
#   con 345 min de cobertura ........ fria el 2,8% del tiempo
#   con 1.020 min (tres trabajos) ... ninguno de los 60 huecos se pasa
#
# LOS MINUTOS SON GRATIS AQUI, y es la razon de que este archivo viva en un
# repositorio publico: GitHub no los cobra. En uno PRIVADO esto seria
# imposible — ahi regala 2.000 minutos al mes, asi que un solo trabajo de
# 345 minutos se llevaria el 17% de la cuota mensual.
#
# ─────────────────────────────────────────────────────────────────────────────
# SE PINGEAN LAS DOS COSAS, Y ESA FUE LA CORRECCION ANTERIOR
# ─────────────────────────────────────────────────────────────────────────────
#
# Una version anterior solo consultaba /auth/v1/health. Mantenia despierta la
# autenticacion y dejaba la BASE DE DATOS congelandose, que es donde estan los
# treinta y cuatro segundos. Se cubria el 21% del problema y se daba por
# resuelto el 100%.
#
# Medido el 1 de noviembre de 2026, con la aplicacion sin arrancar:
#
#   /auth/v1/health ................. 401 en 0,26 s   <- despierta
#   la base por REST ................ 401 en 59,4 s   <- congelada
#   luego ........................... 19,6 s / 1,43 / 1,42
#   signInWithPassword .............. 504 a los 35 s, tres veces seguidas
#
# La autenticacion contestaba en dos decimas y la base no contestaba.

set -uo pipefail

INTERVALO="${INTERVALO:-300}"
DURACION_MIN="${DURACION_MIN:-340}"
LENTO_MS="${LENTO_MS:-3000}"

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "::error::Faltan los secretos NEXT_PUBLIC_SUPABASE_URL o NEXT_PUBLIC_SUPABASE_ANON_KEY en ESTE repositorio."
  echo "Settings -> Secrets and variables -> Actions -> New repository secret."
  exit 1
fi

# Devuelve "codigo ms". El tiempo se mide aqui y no con %{time_total} para
# incluir tambien el fallo de conexion, que es justo el caso lento.
consultar() {
  local ruta="$1" inicio codigo
  inicio=$(date +%s%3N)
  codigo=$(curl -s -o /dev/null -w "%{http_code}" --max-time 45 \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    "${SUPABASE_URL}${ruta}") || codigo="000"
  echo "${codigo} $(( $(date +%s%3N) - inicio ))"
}

inicio=$(date +%s)
fin=$(( inicio + DURACION_MIN * 60 ))

pings=0; lentos=0; fallos=0; peor=0

echo "despertando cada ${INTERVALO}s durante ${DURACION_MIN} min"
echo

while [ "$(date +%s)" -lt "$fin" ]; do
  proximo=$(( $(date +%s) + INTERVALO ))

  # --- Autenticacion ---------------------------------------------------------
  read -r cod_auth ms_auth <<< "$(consultar "/auth/v1/health")"

  # --- Base de datos ---------------------------------------------------------
  #
  # Se pide UNA columna de UNA fila de la tabla mas grande. La peticion llega
  # hasta PostgreSQL y es PostgreSQL quien la rechaza: RLS esta activado sin
  # politicas, asi que el rol `anon` no puede leer nada y la respuesta es 401.
  #
  # Ese rechazo es exactamente lo que se busca. Prueba que la conexion llego a
  # la base —que es lo que la mantiene caliente— y de paso verifica cada cinco
  # minutos que RLS sigue puesto. Un 200 aqui seria una EMERGENCIA: querria
  # decir que las tablas quedaron abiertas a cualquiera con la llave publica.
  read -r cod_bd ms_bd <<< "$(consultar "/rest/v1/Material?select=id&limit=1")"

  pings=$(( pings + 1 ))
  printf '%s  auth %s en %5s ms   base %s en %6s ms\n' \
    "$(date -u +%H:%M:%S)" "$cod_auth" "$ms_auth" "$cod_bd" "$ms_bd"

  if [ "${cod_bd}" = "200" ]; then
    echo "::error::La base devolvió 200 a la llave pública: RLS no está protegiendo la tabla Material."
  elif [ "${cod_bd}" != "401" ] && [ "${cod_bd}" != "403" ]; then
    fallos=$(( fallos + 1 ))
  fi
  [ "${cod_auth}" != "200" ] && fallos=$(( fallos + 1 ))

  [ "${ms_bd}" -gt "$peor" ] 2>/dev/null && peor="${ms_bd}"
  if [ "${ms_bd}" -gt "$LENTO_MS" ] 2>/dev/null; then
    lentos=$(( lentos + 1 ))
    # Solo el primero sale como aviso: setenta anotaciones iguales no se leen,
    # y entonces el aviso que si importa pasa con los demas.
    [ "$lentos" -eq 1 ] && echo "::warning::la base tardó ${ms_bd} ms: seguía fría pese al mantenimiento"
  fi

  ahora=$(date +%s)
  [ "$proximo" -gt "$fin" ] && break
  [ "$proximo" -gt "$ahora" ] && sleep $(( proximo - ahora ))
done

echo
echo "${pings} pings · ${lentos} por encima de ${LENTO_MS} ms · ${fallos} respuestas inesperadas · la peor, ${peor} ms"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "| | |"
    echo "|---|---|"
    echo "| pings | ${pings} |"
    echo "| minutos cubiertos | $(( ( $(date +%s) - inicio ) / 60 )) |"
    echo "| por encima de ${LENTO_MS} ms | ${lentos} |"
    echo "| respuestas inesperadas | ${fallos} |"
    echo "| la peor | ${peor} ms |"
  } >> "$GITHUB_STEP_SUMMARY"
fi

# LOS AVISOS NO TUMBAN EL TRABAJO. Que un servicio este caido un momento no es
# un fallo de este proceso, y un correo de error cada pocas horas se acaba por
# ignorar, que es como se pierde la señal buena.
exit 0
