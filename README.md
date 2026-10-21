# Despertador de Supabase — BIODCORE

Este repositorio contiene **un solo archivo**: un trabajo de GitHub Actions que
llama cada cinco minutos a dos direcciones del proyecto de Supabase de BIODCORE
para que no se enfríe.

**Aquí no hay código de BIODCORE, ni datos, ni credenciales.** Es público por un
motivo concreto y es el único que importa: en un repositorio privado GitHub
regala 2.000 minutos de Actions al mes y **cobra un minuto por ejecución aunque
dure diez segundos**. A una cada cinco minutos son 288 minutos al día, así que
la cuota se gasta en una semana. En un repositorio público los minutos son
ilimitados.

## Qué hace, y por qué dos llamadas

Supabase enfría el proyecto cuando no se usa. Medido el 17 de septiembre de
2026, cuatro consultas seguidas contra la base:

| | Tiempo |
|---|---|
| consulta 1 (en frío) | **34.509 ms** |
| consulta 2 | 1.754 ms |
| consulta 3 | 406 ms |
| consulta 4 | 391 ms |

Treinta y cuatro segundos y medio. Netlify corta mucho antes, así que quien
abría la aplicación tras un rato de inactividad no veía una pantalla lenta: no
veía pantalla.

Se llama a **dos** servicios, y ésa es la corrección: una versión anterior sólo
consultaba `/auth/v1/health`, mantenía despierta la autenticación y dejaba la
**base de datos** congelándose — que es donde estaban los treinta y cuatro
segundos. El ping salía verde todas las veces mientras la aplicación se caía.

La llamada a la base pide una columna de una fila y **espera un 401**. Ese
rechazo lo da PostgreSQL: las tablas tienen RLS activado sin políticas, así que
la llave pública no puede leer nada. Prueba que la conexión llegó hasta la base
—que es lo que la mantiene caliente— y de paso verifica cada cinco minutos que
RLS sigue puesto. **Un 200 ahí sería una emergencia.**

## Puesta en marcha

En **Settings → Secrets and variables → Actions → New repository secret**, de
este repositorio:

| Secreto | Qué es |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | La dirección del proyecto en Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | La llave pública (`anon`) |

Después, **Actions → Mantener despierto Supabase → Run workflow** para
comprobarlo sin esperar al reloj. El registro debe decir algo como:

```
autenticación: 200 en 774 ms
base de datos:  401 en 829 ms
```

## Que aquí no entre nunca la llave de servicio

La llave `anon` **es pública por diseño**: viaja en el JavaScript que descarga
cualquier navegador que abra la aplicación, y con RLS sin políticas no da acceso
a nada. Por eso puede estar en los secretos de un repositorio público sin que
eso cambie nada.

`SUPABASE_SERVICE_ROLE_KEY` es otra cosa: **se salta RLS entera** y no pinta en
un despertador. No debe aparecer aquí bajo ningún concepto.

## GitHub lo desactiva solo a los 60 días

**En un repositorio público, GitHub desactiva los workflows programados cuando
el repositorio lleva 60 días sin actividad.** Éste no va a tener ninguna —es un
archivo que no se toca— así que va a pasar.

Llega un correo de aviso antes. Hay dos salidas:

- entrar en **Actions** y reactivarlo, que es un clic; o
- adelantarse cada par de meses con un commit vacío:

```powershell
git commit --allow-empty -m "Mantener el programador activo"
git push
```

**Si un día notas que la aplicación vuelve a tardar medio minuto en abrir por
la mañana, mira esto primero.** Es la causa más probable, y no avisa de otra
forma: el workflow no falla, simplemente deja de ejecutarse.

## Si deja de hacer falta

Se borra el repositorio y ya está. La aplicación sigue funcionando; lo que
vuelve es la espera de la primera apertura del día.
