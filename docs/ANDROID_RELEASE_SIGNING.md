# Firma de releases Android

Los APK/AAB de CI y staging se firman con la clave debug y **no son artefactos de distribución**. Los builds con `APP_ENV=production` deben usar una clave de release dedicada. La configuración Gradle falla de forma explícita si falta esa clave; no se permite publicar accidentalmente un APK firmado con debug.

## Antes de crear una clave

Si España Outdoor ya se ha distribuido mediante Google Play, reutiliza la clave de subida (upload key) registrada para la aplicación. No generes una clave nueva ni cambies el certificado de una aplicación existente sin comprobar antes Play Console. Si Play App Signing está habilitado, normalmente se usa aquí la upload key, no la app-signing key que conserva Google.

Conserva una copia de seguridad cifrada de la clave y sus contraseñas fuera de GitHub. La pérdida de la clave puede impedir actualizar la aplicación si no se utiliza Play App Signing con un procedimiento de recuperación.

## Crear una clave nueva (solo si todavía no existe)

En Windows PowerShell, con un JDK instalado:

```powershell
keytool -genkeypair -v -keystore .\espana-outdoor-upload.jks -storetype JKS -keyalg RSA -keysize 4096 -validity 10000 -alias espana-outdoor-upload
```

Keytool solicitará la contraseña del almacén, la contraseña de la clave y los datos del certificado. Guarda las contraseñas en un gestor seguro.

Obtén la huella SHA-256 del certificado:

```powershell
keytool -list -v -keystore .\espana-outdoor-upload.jks -alias espana-outdoor-upload
```

Copia el valor `SHA256` sin los dos puntos para el secreto `ANDROID_RELEASE_CERT_SHA256`.

Convierte el almacén a Base64 para introducirlo como secreto de GitHub:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path .\espana-outdoor-upload.jks))) | Set-Clipboard
```

El contenido del portapapeles es el valor de `ANDROID_RELEASE_KEYSTORE_BASE64`. No lo pegues en un chat, issue, commit ni log.

## Secretos requeridos en GitHub

En el repositorio, abre **Settings → Secrets and variables → Actions** y crea estos secretos:

| Secreto | Valor |
|---|---|
| `ANDROID_RELEASE_KEYSTORE_BASE64` | Almacén JKS codificado en Base64 |
| `ANDROID_RELEASE_STORE_PASSWORD` | Contraseña del almacén |
| `ANDROID_RELEASE_KEY_ALIAS` | Alias de la clave |
| `ANDROID_RELEASE_KEY_PASSWORD` | Contraseña de la clave |
| `ANDROID_RELEASE_CERT_SHA256` | Huella SHA-256 del certificado, 64 caracteres hexadecimales |

No almacenes el JKS, contraseñas ni contenido Base64 en el repositorio. `.gitignore` excluye los ficheros `.jks` y `.keystore`.

## Verificación

El workflow **Release candidate**:

1. exige los cinco secretos y decodifica el almacén en el directorio temporal del runner;
2. inyecta las variables de firma solo en el entorno de build;
3. configura Gradle para seleccionar la clave release en producción;
4. genera APK y AAB;
5. verifica los recursos obligatorios y compara el certificado SHA-256 de ambos artefactos con `ANDROID_RELEASE_CERT_SHA256`.

Si falta una variable, el almacén no es válido o el certificado no coincide, el workflow falla y no produce un candidato de producción válido.

Los workflows CI/staging pueden seguir usando la firma debug para pruebas internas. Sus artefactos no deben distribuirse ni subirse a Google Play.
