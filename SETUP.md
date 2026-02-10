# Tycoon Kit Setup (Paso a paso)

## 1) Crea la estructura del sistema
- `ReplicatedStorage/TycoonKit/Config/GameConfig` (ModuleScript)
- `ReplicatedStorage/TycoonKit/Remotes/RequestPurchase` (RemoteEvent)
- `ReplicatedStorage/TycoonKit/Remotes/PurchaseResult` (RemoteEvent)
- `ReplicatedStorage/TycoonKit/Remotes/CashUpdated` (RemoteEvent)
- `ReplicatedStorage/TycoonKit/Remotes/DropVisual` (RemoteEvent)
- `ReplicatedStorage/TycoonKit/Remotes/CollectDrop` (RemoteEvent)
- `ServerScriptService/TycoonKitServer/Main.server.lua` (Script)
- `ServerScriptService/TycoonKitServer/Services/ValidationService` (ModuleScript)
- `StarterPlayer/StarterPlayerScripts/TycoonClient/DropVisual.client.lua` (LocalScript)
- `StarterPlayer/StarterPlayerScripts/TycoonClient/ButtonInteract.client.lua` (LocalScript)
- `StarterPlayer/StarterPlayerScripts/TycoonClient/CashHud.client.lua` (LocalScript)

## 2) Estructura visual recomendada de cada Tycoon
```text
Workspace
└── Tycoons
    └── Tycoon_1 (Model) [Attribute: OwnerUserId]
        ├── Buttons
        │   ├── Dropper1 (Model)
        │   │   ├── Head (Part)
        │   │   └── Configuration (Configuration)
        │   │       ├── Price (NumberValue)
        │   │       ├── Prerequisite (StringValue, opcional)
        │   │       └── GamepassId (NumberValue, opcional)
        │   └── Upgrader1 (Model)
        │       ├── Head (Part)
        │       └── Configuration (Configuration)
        │           ├── Price (NumberValue)
        │           ├── Prerequisite (StringValue, opcional)
        │           └── GamepassId (NumberValue, opcional)
        ├── Structures
        │   ├── Dropper1 (Model)  <- mismo nombre del botón
        │   └── Upgrader1 (Model)
        ├── Droppers
        │   └── Dropper1 (Model)
        │       ├── DropperBase (Model con piezas)
        │       ├── Mouth (Part)
        │       └── Configuration (Configuration)
        │           ├── BaseValue (NumberValue)
        │           ├── Rate (NumberValue)
        │           └── Tag (StringValue)
        └── Upgraders
            └── Upgrader1 (Model)
                ├── UpgradeBase (Model con piezas)
                └── Configuration (Configuration)
                    ├── AddAmount (NumberValue)
                    └── TagFilter (StringValue)
```

## 3) Lógica de compra y progreso (actual)
- Todos los botones usan `Price` (cash).
- Si el botón tiene `GamepassId` (> 0), además exige que el jugador tenga ese gamepass.
- `Prerequisite` vacío o ausente = sin requisito.
- El botón desbloquea `Structures/<mismoNombre>`.
- Si el botón desbloquea un upgrader con el mismo nombre en `Upgraders`, suma `AddAmount` al grupo `TagFilter`.
- El server responde por `PurchaseResult(ok, buttonName, reason)`.

## 4) Lógica de drops (actual)
- Solo droppers comprados generan drops.
- Valor por drop = `BaseValue + bonusPorTag`.
- Luego aplica multiplicador de dinero por gamepass (solo el mayor: x3 > x2).
- El servidor crea `dropId` lógico y dispara `DropVisual` al cliente.
- El cliente debe reclamar con `CollectDrop(dropId)`.
- El servidor valida `dropId` pendiente y acredita dinero.
- El server avisa dinero actualizado con `CashUpdated(cash)`.

## 5) Configuración global (GameConfig)
Edita IDs en:
- `Monetization.MoneyX2PassId`
- `Monetization.MoneyX3PassId`
- `Monetization.AutoCollectorPassId`
- `Sounds.*`

## 6) Reglas de validación aplicadas
### Botones
- Rechaza botón sin `Configuration`
- Rechaza si falta `Price`
- Rechaza si `Price < 0`
- Rechaza si no cumple `Prerequisite`
- Rechaza si no existe estructura homónima
- Rechaza compra duplicada
- Rechaza si no tiene cash suficiente
- Rechaza si requiere `GamepassId` y el jugador no lo posee

### Droppers
- Rechaza si falta `Configuration`
- Rechaza si falta `BaseValue`
- Rechaza si falta `Rate`
- Rechaza si falta `Tag`

### Upgraders
- Rechaza si falta `Configuration`
- Rechaza si falta `AddAmount`
- Rechaza si falta `TagFilter`

## 7) Scripts cliente
- `DropVisual.client.lua`: visual de drops + claim `CollectDrop`.
- `ButtonInteract.client.lua`: ClickDetector en `Buttons/*/Head`, envía `RequestPurchase(buttonName)`, y aplica feedback visual/sonoro en éxito/error.
- `CashHud.client.lua`: muestra cash en HUD con `CashUpdated` y reproduce sonido de collect cuando el cash sube.


## 8) Persistencia (DataStore)
- Si `GameConfig.Progression.SaveEnabled = true` y `StartFromZeroOnJoin = false`, el server guarda/carga:
  - `cash`
  - lista de compras (`purchased`)
- Guardado automático cada `AutosaveInterval` segundos y al salir/cerrar servidor.
- Si `StartFromZeroOnJoin = true`, ignora datos guardados y empieza desde 0.
