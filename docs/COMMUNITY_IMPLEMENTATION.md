# Comunidad social outdoor — implementación por fases

Estado: **prototipo de interfaz; backend social no implementado**.

## Decisiones de producto

- La comunidad forma parte de España Outdoor y reutiliza la identidad de la aplicación.
- Mapbox es el único motor cartográfico autorizado.
- Las vistas iniciales son «Siguiendo» y «Explorar».
- Los tipos de contenido previstos son publicaciones de texto/fotografía, rutas compartidas y descubrimientos outdoor.
- La ubicación exacta es privada por defecto; el usuario controla la visibilidad por publicación.
- No se mostrará ubicación GPS en tiempo real en el feed.
- Las fotografías deberán perder sus metadatos GPS antes de publicarse.
- Los informes de usuarios se separarán de los datos oficiales y tendrán estados de revisión.

## Bloqueo previo a datos reales

El cliente móvil utiliza un flujo OIDC con `flutter_appauth`; la estrategia de identidad web no se considera validada como identidad compartida. Antes de servir publicaciones reales hay que confirmar que web y Android resuelven el mismo identificador de usuario y que el backend verifica los tokens. No se debe conectar Neon Auth en paralelo sin demostrar una federación o estrategia común.

El backend existente `services/source-gateway` está diseñado para fuentes oficiales y no es una API social. No debe ampliarse de forma oportunista para almacenar perfiles o publicaciones. Hace falta definir un servicio social con persistencia, migraciones, autorización y pruebas propias.

## Contrato inicial propuesto

- `GET /v1/community/feed?scope=following|explore&cursor=...`
- `POST /v1/community/posts` — texto, tipo, visibilidad y referencias opcionales a imágenes/rutas.
- `GET /v1/community/posts/{postId}`
- `DELETE /v1/community/posts/{postId}` — solo propietario o moderación autorizada.
- `POST /v1/community/posts/{postId}/likes` y `DELETE .../likes`
- `POST /v1/community/posts/{postId}/comments`
- `PUT /v1/community/posts/{postId}/bookmark` y `DELETE .../bookmark`
- `PUT /v1/community/users/{userId}/follow` y `DELETE .../follow`
- `POST /v1/community/reports` y `POST /v1/community/blocks`

Los nombres son propuesta de contrato, no endpoints existentes.

## Reglas mínimas del modelo

- Identidad: usar el identificador estable validado por el proveedor de identidad común; no confiar en un `userId` enviado por el cliente.
- Publicación: `id`, `authorId`, `body`, `visibility`, `createdAt`, `updatedAt`, `status`, `routeId?`, `locationVisibility`.
- Imagen: referencia de objeto, tipo MIME verificado, tamaño máximo, hash y estado de procesamiento; quitar EXIF/GPS y generar miniaturas en servidor.
- Interacción: restricciones únicas para evitar likes, follows y guardados duplicados.
- Moderación: reportes trazables, bloqueo aplicado en servidor, borrado lógico/auditable y herramientas de revisión.
- Paginación por cursor y límites de petición; validar y limitar texto, imágenes y frecuencia.
- Ubicación: nunca exponer coordenadas exactas de forma predeterminada; generalizar o eliminar metadatos sensibles.

## Fases de entrega

1. **Interfaz y contrato:** feed, estados vacíos/error, borrador de publicación y diseño de contratos. El feed actual contiene solo datos de demostración.
2. **Identidad y servicio social:** validar identidad común, crear API y migraciones, permisos por propietario y pruebas de autorización.
3. **Publicaciones e imágenes:** almacenamiento de objetos verificado, miniaturas y limpieza EXIF.
4. **Rutas y GPX:** enlazar registros reales y estadísticas verificadas; diferenciar GPX importado de ruta calculada por Valhalla.
5. **Interacciones y perfiles:** likes, comentarios, guardados, seguidores y perfil comunitario.
6. **Moderación y privacidad:** bloqueo, denuncia, borrado y pruebas de visibilidad.
7. **Offline personal:** solo contenido guardado por el usuario, con fecha de sincronización y aviso de obsolescencia.

## Criterio para declarar una fase operativa

Se requieren pruebas de API y autorización, migraciones verificadas, pruebas automatizadas, manejo de errores de red y validación de datos reales. Una pantalla o una compilación no demuestran que las publicaciones estén almacenadas ni sincronizadas.
