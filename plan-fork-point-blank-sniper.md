# Plan de implementación: fork de Point Blank Sniper para flipping

Documento para entregar a un agente de programación. Explicaciones en español; nombres de opciones, objetos y conceptos del juego en inglés. El alcance principal es WoW Retail.

## 1. Encargo y resultado esperado

Implementar un fork pequeño y mantenible de Point Blank Sniper (PBS) que combine:

- La velocidad de su modo Keys para recorrer listas grandes.
- Filtros de precio y liquidez basados en datos de TradeSkillMaster (TSM).
- Compra iniciada manualmente con una tecla o la rueda, con una comodidad parecida a la macro de compra de TSM.
- Una cola de oportunidades estable, que permita avanzar después de comprar o descartar un resultado.

El usuario quiere revisar un catálogo gigantesco de posibles flips, del orden de 4.000 objetos o más, especialmente recipes, battle pets y otros objetos revendibles. TSM Shopping permite sus condiciones y le resulta cómodo para comprar, pero sus escaneos grandes tardan demasiado. PBS ofrece Keys, pero su configuración actual no permite el filtro de liquidez solicitado.

No hace falta reproducir todo TSM: conservar su addon como fuente de datos, contabilidad y herramienta de publicación. El fork cubre búsqueda, evaluación de oportunidades y compra manual.

## 2. Repositorio, entorno y lenguaje

- Upstream: https://github.com/TheMouseNest/PointBlankSniper
- Revisión inspeccionada: `aae36edf6a5c9b596b419def78a6f30fceb7debe`, del 14 de octubre de 2026, mensaje `Fixes for 12.1.5`.
- Antes de implementar, comprobar si upstream ha cambiado y registrar el commit elegido. Las observaciones de este documento corresponden a esa revisión.
- Lenguaje: Lua del entorno de addons de WoW; UI definida en XML y Lua.
- `PointBlankSniper.toc`: manifiesto, dependencias, archivos y SavedVariables.
- Dependencia obligatoria actual: Auctionator. El addon reutiliza sus listas, componentes de UI, EventBus, utilidades y wrappers de la AH.
- TSM es necesario para el nuevo modo de filtros. El código upstream consulta `TSM_API` aunque su TOC no lo declara como OptionalDeps: revisar el orden de carga y añadir la declaración si procede.
- La aplicación de escritorio de TSM proporciona los datos regionales. Su API dentro del juego puede existir sin que una fuente tenga datos para un objeto.
- SavedVariables actuales: `POINT_BLANK_SNIPER_CONFIG` y `POINT_BLANK_SNIPER_ITEM_CACHE`.
- No introducir Node, un backend, un LLM ni servicios web para el funcionamiento del addon. Las herramientas externas de desarrollo son opcionales.
- Licencia MIT: conservar LICENSE y los avisos de copyright de plusmouse; documentar cambios y atribución.

El MVP se valida en Retail. No asumir que funciona en TBC Anniversary, Classic o Forever porque upstream incluya otros clientes: esas compatibilidades quedan fuera de este primer alcance.

## 3. Funcionamiento actual de PBS, comprobado en el código

### 3.1 Listas y escaneo

PBS aparece como una pestaña de la AH registrada mediante Auctionator. Selecciona una Shopping List de Auctionator; no consume directamente grupos y operaciones de TSM.

`Utilities.ConvertList()` transforma las entradas de Auctionator en términos con nombre, precio máximo opcional, filtros de item level, reagent tier y coincidencia exacta.

En Keys:

1. Usa su caché local de nombres e ItemKeys para resolver esos términos.
2. `Scan.GetItemKeys()` genera las claves y sus asociaciones con precios y términos originales.
3. `ScannerKeyCache:SetList()` aplica filtros de categoría y un `keyFilter` opcional.
4. `DoNextSearch()` llama a `C_AuctionHouse.SearchForItemKeys(itemKeys, {})` en lotes de **100 Keys**.
5. Recibe resúmenes con `minPrice` y `totalQuantity` y publica resultados mediante el EventBus.

La caché de Keys se alimenta con escaneos y se combina al cerrar/cambiar de contexto. Un objeto sin Key conocida no debe contarse como consultado sin ofertas. Mantener el modo Blank como mecanismo para poblar la caché y explicar las claves ausentes.

El modo Blank utiliza una consulta Browse amplia, pagina los resultados y los cruza con los términos por nombre. No tiene el mismo coste que Keys. Conservar los modos existentes.

### 3.2 Precio y un detalle importante

`PriceCheck.Get()` permite fuentes predefinidas como DBMarket, DBRecent, DBRegionMarketAvg y DBRegionSaleAvg. `TSMMixin` consulta `TSM_API.GetCustomPriceValue()` y aplica el porcentaje configurado.

En ambos scanners, cuando una entrada de la lista incluye un precio manual, upstream compara contra ese precio y **no llama a `priceCheck:CheckResult()`**. Por tanto, añadir liquidez solo dentro de TSMMixin no bastaría: esos objetos podrían saltarse el nuevo filtro. Resolver explícitamente este punto.

La conversión actual a TSM usa `p:<speciesID>` para battle pets e `i:<itemID>` para objetos. Validar qué formato admite la versión instalada de TSM y conservar las variantes necesarias; no asumir que un precio por itemID distingue todas las calidades, bonusIDs o variantes.

### 3.3 Compra

Al seleccionar un resultado se emite `OpenBuyView`, se detiene el escaneo y se abre el panel Buy. Este pide las ofertas detalladas con `Auctionator.AH.SendSearchQueryByItemKey()`.

`PointBlankSniperBuyFrameMixin:BuyNow()` ya existe:

- Para objetos individuales, utiliza el auctionID y `C_AuctionHouse.PlaceBid()` con el buyout.
- Para commodities, inicia `StartCommoditiesPurchase()` y procesa la cotización mediante los eventos de commodities, confirmando o cancelando según el precio.
- El botón queda desactivado durante la solicitud.

En upstream, `expectedPrice` procede del precio detectado en el resumen. No confundir ese precio con el máximo calculado por la regla. Mantener ambos valores diferenciados.

El panel no es una cola completa ni confirma de forma general el éxito final para avanzar. Su botón XML utiliza parentKey, sin un nombre global de compra explícito: no dar por válida una macro `/click` inventada. Inspeccionar el frame real y escoger un mecanismo de binding admitido por el cliente.

## 4. Reglas de negocio del MVP

### 4.1 Condición inicial exacta

Mostrar una oportunidad únicamente si:

```text
precio unitario actual <= 0.40 × DBRegionSaleAvg
AND DBRegionSoldPerDay > 0.02
```

Los valores 40 % y 0.02 deben ser editables desde la UI y persistirse. El operador de liquidez es estrictamente `>`, por lo que 0.02 exacto no pasa.

**No confundir las métricas:**

- `DBRegionSoldPerDay`: volumen medio diario; no es un porcentaje.
- `DBRegionSaleRate`: tasa de venta; 0.02 representa un 2 %.

El último requisito expresado fue Daily Sold > 0.02, aunque antes en la conversación se probó > 100. El valor inicial de este fork será **0.02**. Opcionalmente ofrecer un selector explícito de métrica, conservando Daily Sold como valor por defecto. No cambiarlo silenciosamente a Sale Rate.

0.02 unidades/día equivale matemáticamente a una unidad cada 50 días en esa estadística; no es una predicción del tiempo de venta del usuario. Por ello, un objeto con Daily Sold = 5.328 **sí pasa el nuevo umbral**; no reutilizar ese ejemplo como caso rechazado salvo que se configure un mínimo de 100.

### 4.2 Ausencia de datos y validación

- Si TSM no está disponible, bloquear el modo dependiente de TSM con un mensaje claro.
- Si falta Daily Sold o DBRegionSaleAvg para un objeto, excluirlo de oportunidades comprables y registrar el motivo en diagnóstico.
- Rechazar precios de referencia no positivos, números no válidos y ofertas sin buyout.
- No sustituir silenciosamente una fuente ausente por DBMarket, VendorSell o un precio de compra de 1 cobre.
- Si el usuario cambia parámetros, invalidar los resultados y cachés de evaluación afectados antes de continuar.

### 4.3 Precios manuales en las listas

Con el nuevo modo activo, ninguna entrada con precio manual puede saltarse el filtro de liquidez. La política inicial será:

```text
máximo efectivo = min(40 % de DBRegionSaleAvg, máximo manual de la entrada)
```

Si no hay máximo manual, usar solo el regional. La liquidez y la presencia de datos se comprueban siempre. Si un objeto coincide con varias entradas, conservar la asociación con el término que lo aceptó y definir de forma determinista cómo se resuelven sus límites. No utilizar una coincidencia amplia para vulnerar un límite específico sin una política documentada.

### 4.4 Unidades, pets y variantes

- Trabajar en copper para dinero; el volumen diario puede ser decimal.
- Comparar precio unitario con precio unitario. En lotes, conservar por separado precio total y cantidad.
- Para battle pets, usar speciesID y conservar identidad, nivel y calidad cuando sean relevantes para la oferta. No valorar todos como el objeto genérico de jaula.
- No colapsar ItemKeys diferentes en una misma compra. Separar la identidad de la oferta de la clave usada para consultar una fuente regional.

## 5. Arquitectura propuesta

### 5.1 Evaluador común

Crear un evaluador reutilizable que reciba ItemKey, precio, término de lista y configuración, y devuelva al menos:

```text
eligible, reason, maxUnitPrice, regionSaleAvg, dailySold, priceFraction
```

Debe usarse en Keys, Blank y la revalidación previa a comprar. Separar la elegibilidad sin precio actual de la comprobación final de precio.

Los puntos de integración sugeridos son `PriceCheck`, `ScannerKeyCache:SetList()`, `ScanItemKeyResults()`, `ScannerNameCache:DoShoppingListSearch()` y el panel Buy. Son sugerencias basadas en la revisión inspeccionada: adaptar sin una refactorización innecesaria.

### 5.2 Prefiltrado y rendimiento

- En Keys, excluir antes de enviar las consultas los objetos que no cumplen liquidez o no tienen referencia regional.
- Consultar los datos TSM con caché por identidad de precio y versión de configuración durante una pasada, sin repetirlos cada frame.
- Revalidar los resúmenes recibidos, aunque ya se haya prefiltrado.
- En Blank, filtrar antes de añadir a resultados, siempre también para entradas con precio manual.
- No hacer una consulta detallada de subastas por cada uno de los 4.000 objetos: reservarla para oportunidades que se vayan a preparar para compra.
- Mantener el tamaño de lote existente salvo que la documentación y pruebas justifiquen cambiarlo.
- Respetar throttling y respuestas del juego; manejar fallos o timeouts sin bucles agresivos.
- Procesar listas grandes sin bloquear la UI: trabajo por lotes si resulta necesario.

Medir tiempo de preparación local y tiempo de escaneo por separado. Comparar upstream y fork con la misma lista, reino, condiciones y caché. No prometer un tiempo fijo de tres segundos ni una mejora universal frente a TSM.

### 5.3 UI y configuración

Mantener la interfaz de PBS/Auctionator y añadir:

- Activación del modo TSM Flipping.
- Maximum % of Region Sale Avg, inicialmente 40.
- Minimum Region Sold/Day, inicialmente 0.02, con decimales.
- Tratamiento visible de datos ausentes: excluidos.
- Keybinding de compra y opción de rueda con modificador.
- Columnas Region Sale Avg, Region Sold/Day y Price % of Region Sale Avg; ordenar resultados sin perder la selección.
- Estado de compra: buscando, listo, esperando respuesta, comprado, vendido/no disponible o error, con texto claro.

Conservar traducciones upstream. Añadir como mínimo textos en inglés y español; no codificar nombres localizados de objetos para identificar las ofertas.

Los usuarios deben entender qué significa cada número. Si se añade un descuento, definirlo como `(referencia - precio) / referencia`; si se añade retorno sobre coste, usar otro nombre y otra fórmula. No presentar el descuento como beneficio garantizado tras comisiones.

## 6. Entrada de grupos grandes

### MVP

Seguir utilizando Shopping Lists de Auctionator. Documentar cómo preparar/importar una lista grande y el puente desde los grupos TSM existentes. Comprobar antes de recomendar una utilidad externa de conversión; no asumir que su versión actual funciona.

La lista resultante debe conservar identidades y coincidencias exactas cuando proceda, pets y ausencia de precios manuales heredados inesperados. Probar el flujo completo con una muestra exportada de TSM.

### Segunda fase

Valorar seleccionar directamente grupos de TSM o importar una lista de itemIDs/pet speciesIDs. Usar APIs públicas de TSM tras verificarlas; no inventar métodos ni leer SavedVariables internas si existe una API estable. Si el importador nativo de grupos es costoso, entregar primero la solución de listas y documentar esa limitación.

## 7. Compra rápida con teclado o rueda

### 7.1 Primera entrega

Vincular la acción de compra ya existente a una tecla configurable, preferiblemente visible en Key Bindings. Añadir un binding de rueda opcional con modificador, por ejemplo Ctrl + rueda.

El binding solo debe actuar con la AH y el panel apropiado visibles, una oferta preparada, botón habilitado y ninguna operación pendiente. Fuera de ese contexto debe conservar el comportamiento anterior de la tecla/rueda. No sobrescribir permanentemente los bindings globales del usuario.

Inspeccionar la ruta admitida por las APIs actuales: binding de click, botón con nombre estable u otro mecanismo permitido. No prometer una macro concreta antes de probarla. Cada intento de compra debe iniciarse mediante una pulsación o acción física del usuario. No generar compras nuevas desde timers ni respuestas del servidor; las fases de cotización/confirmación del flujo de una compra deben respetar lo que permita la API actual.

### 7.2 Cola y avance

- Selección estable por identidad, nunca por índice de fila.
- Al comprar o cambiar el orden de resultados, la rueda no debe adquirir otro objeto por una referencia obsoleta.
- Una sola compra en curso. Las pulsaciones adicionales durante Loading o Buying no generan solicitudes duplicadas ni se acumulan para dispararse más tarde.
- Cuando se confirme una compra, marcar/eliminar la oferta procesada y preparar la siguiente si Rapid Buy está activado. La siguiente compra sigue requiriendo otra acción física.
- Si ya se vendió, permitir saltarla y preparar la siguiente. No reintentar una compra indefinidamente.
- Pausar el scanner durante la consulta detallada y la compra, aprovechando el comportamiento actual de `OpenBuyView`. Reanudar solo cuando se cierre o finalice correctamente el contexto de compra.

Modelar estados explícitos, por ejemplo Idle → Loading → Ready → Buying → Success/Unavailable/Error. Añadir un identificador de generación/contexto para ignorar callbacks o eventos correspondientes a una selección anterior. Identificar los eventos reales de éxito y error de cada tipo de compra; no deducir éxito porque el botón se haya desactivado ni por un timer fijo.

### 7.3 Límites de precio y cantidad

Antes de armar el botón y antes de confirmar una compra, verificar identidad, regla de liquidez y máximo efectivo. Por defecto, no aceptar un precio superior al seleccionado en el resumen, aunque aún esté por debajo del máximo regional: mantener explícita esa política y mostrar el precio que se va a pagar.

Para commodities, comprobar unitPrice y totalPrice, cantidad elegida, disponibilidad, presupuesto y límites configurados. No comprar automáticamente todo el stock del tramo más barato sin mostrar/limitar la cantidad. Para objetos individuales, verificar auctionID y buyout actuales. Conservar y endurecer las comprobaciones de precio existentes.

Considerar límites configurables de cantidad por objeto y gasto por compra. Deben estar visibles, sin valores restrictivos ocultos. Al cerrar la AH o cambiar de selección, cancelar y limpiar contextos pendientes según permita la API.

## 8. Plan de ejecución por fases

1. **Auditoría breve:** fijar revisión, comprobar dependencias, licencia y versión de Retail; explicar los puntos de integración encontrados.
2. **Filtros y UI:** implementar el evaluador, datos ausentes, límites manuales y configuración persistente. Validar primero con datos simulados.
3. **Keys eficiente:** integrar prefiltrado y caché, garantizar el mismo filtro en Blank y añadir contadores de diagnóstico.
4. **Compra con tecla:** reutilizar el flujo Buy, registrar un binding contextual y verificar bloqueos e identidad.
5. **Rapid Buy:** cola estable, avance tras confirmación y manejo de resultados vendidos, precio cambiado, errores y eventos tardíos.
6. **Validación en juego y entrega:** probar con objetos de poco valor y lista grande; documentar resultados reales y los casos que todavía necesitan prueba.

Se autoriza al agente a preparar e implementar el fork y entregar un paquete local revisable. No se solicita publicar en CurseForge, hacer un push a una cuenta remota ni abrir un PR por cuenta del usuario. La compra de objetos reales para pruebas se valida manualmente en el juego por el usuario.

## 9. Pruebas de aceptación

Las pruebas unitarias se centran en reglas económicas e identidad/estado; las pruebas del cliente se documentan por separado. No considerar una simulación Lua como validación de un binding protegido dentro del juego.

| Caso | Resultado esperado |
| --- | --- |
| Region Sale Avg = 1.000 g; Daily Sold = 0.03; precio = 390 g | Aceptado; máximo = 400 g |
| Mismos datos; precio = 400 g | Aceptado; el precio usa <= |
| Mismos datos; precio = 400 g 00 s 01 c | Rechazado |
| Daily Sold = 0.019 o exactamente 0.02 | Rechazado |
| Daily Sold = 0.021 | Pasa liquidez |
| Falta Daily Sold, falta precio regional o falta TSM | No hay una oportunidad comprable; motivo visible |
| Término con precio manual y sin liquidez | Rechazado; el límite manual no evita el filtro |
| Máximo regional 400 g; manual 300 g; precio 350 g | Rechazado |
| Un mismo objeto coincide con varios términos | Regla determinista; sin duplicados ni saltos de límite |
| Dos pets con distinto speciesID o dos ItemKeys distintos | No se mezclan sus precios ni sus compras |
| Oferta vendida mientras se prepara | No compra otra oferta o identidad por accidente |
| El precio aumenta o cambia la cantidad cotizada | No supera los límites ni el precio autorizado |
| Rueda rápida mientras llega una respuesta | Sin solicitudes duplicadas ni compras diferidas por pulsaciones en cola |
| Se ordenan/refrescan los resultados al comprar | La selección conserva identidad |
| Se cierra la AH o se cambia de pestaña | Binding/contextos de compra se desactivan correctamente |
| Cambio de configuración, /reload y reapertura | Configuración persistida; evaluación actualizada |
| Lista de unas 4.000 entradas, con caché fría y caliente | Sin bloqueo significativo; tiempos y claves desconocidas registrados |
| Otro addon consulta la AH o llega un evento anterior | La compra no se atribuye a otra selección; probar dentro del cliente |

## 10. Diagnóstico y entregables

Mostrar o registrar bajo una opción Debug: entradas recibidas, Keys resueltas, claves desconocidas, descartes por liquidez/datos/precio, consultas enviadas, oportunidades, tiempo por pasada y motivos de compra bloqueada. No volcar miles de líneas de chat en uso normal.

Entregar:

- Fork funcional o parche reproducible con versión y commit base.
- README con instalación en `_retail_/Interface/AddOns`, dependencias, preparación de listas, opciones y bindings.
- Aclaración de si reemplaza PBS o convive con él. Preferir reemplazo controlado para el MVP; no cargar dos copias con globals iguales. Documentar cómo evitar que el gestor de addons sobrescriba el fork.
- Configuración previa conservada mediante migración no destructiva; documentar backup de SavedVariables.
- Pruebas de lógica y checklist de pruebas realizadas/no realizadas en juego.
- Medición básica frente a upstream; sin prometer mejoras no medidas.
- LICENSE y atribución de upstream.

Prioridad: filtros correctos → compra manual con tecla → cola rápida → comodidad de importación. Mantener el escaneo Keys; no convertir la solución en una búsqueda detallada por cada objeto.

## 11. Fuentes para el agente

Revisar los archivos en la revisión fijada o en el commit elegido antes de modificar:

- [Repositorio y licencia](https://github.com/TheMouseNest/PointBlankSniper)
- [TOC](https://github.com/TheMouseNest/PointBlankSniper/blob/aae36edf6a5c9b596b419def78a6f30fceb7debe/PointBlankSniper.toc)
- [Keys scanner](https://github.com/TheMouseNest/PointBlankSniper/blob/aae36edf6a5c9b596b419def78a6f30fceb7debe/Source/Scan/KeyCache.lua)
- [Blank scanner](https://github.com/TheMouseNest/PointBlankSniper/blob/aae36edf6a5c9b596b419def78a6f30fceb7debe/Source/Scan/NameCache.lua)
- [Generación de ItemKeys](https://github.com/TheMouseNest/PointBlankSniper/blob/aae36edf6a5c9b596b419def78a6f30fceb7debe/Source/Scan/GetItemKeys.lua)
- [Selección de fuente](https://github.com/TheMouseNest/PointBlankSniper/blob/aae36edf6a5c9b596b419def78a6f30fceb7debe/Source/PriceCheck/Get.lua)
- [Comprobadores de precio](https://github.com/TheMouseNest/PointBlankSniper/blob/aae36edf6a5c9b596b419def78a6f30fceb7debe/Source/PriceCheck/Mixins.lua)
- [Compra](https://github.com/TheMouseNest/PointBlankSniper/blob/aae36edf6a5c9b596b419def78a6f30fceb7debe/Source/Buy/Main.lua)
- [Panel de compra XML](https://github.com/TheMouseNest/PointBlankSniper/blob/aae36edf6a5c9b596b419def78a6f30fceb7debe/Source/Buy/Main.xml)
- [Coordinación de la pestaña](https://github.com/TheMouseNest/PointBlankSniper/blob/aae36edf6a5c9b596b419def78a6f30fceb7debe/Source/Tab/Main.lua)
- [Proveedor de resultados](https://github.com/TheMouseNest/PointBlankSniper/blob/aae36edf6a5c9b596b419def78a6f30fceb7debe/Source/Tab/DataProvider.lua)
- [Configuración persistente](https://github.com/TheMouseNest/PointBlankSniper/blob/aae36edf6a5c9b596b419def78a6f30fceb7debe/Source/Config/Main.lua)
- [Documentación de la API de TSM](https://support.tradeskillmaster.com/en_US/api-documentation/what-is-the-tsm-addon-api-and-how-do-i-use-it)
- [Fuentes de valores de TSM](https://support.tradeskillmaster.com/en_US/custom-strings/which-value-sources-can-i-use-and-what-do-they-mean)
- [Documentación generada de la API de Auction House](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuctionHouseDocumentation.lua)

Las secciones sobre el código existente están verificadas por lectura de upstream. La arquitectura del fork es una propuesta. El funcionamiento de los bindings y los eventos de compra deberá confirmarse en el cliente; este documento no afirma que esas modificaciones ya estén implementadas ni probadas.

