# PinTrip

macOS 旅游地点标注与规划工具。搜索地点 → 加入计划 → 在地图上查看全部标注 → 按计划一键管理。

## 功能

- **旅游计划**：新建计划时选择起止日期，自动生成 Day 1..N；可随时改日期范围
- **按天行程**：中间栏按天分区显示地点，**空天也会列出**（显示「拖动地点到这里」），创建后即可把所有天看到
- **拖动调天**：按住地点行可拖到任意天；天内拖动调顺序，跨天拖动改归属
  - 拖动时目标天整块高亮描边，行间显示蓝色插入线指示落点
  - 天内排序与跨天移动已统一为一套拖放（原 `onMove` 已移除，两者共存会抢手势）
  - 移动后**源天和目标天都会重排 `sortOrder`**，避免留下序号空洞
- **地点搜索**：`MKLocalSearchCompleter` 边打边联想
- **预览确认**：选中搜索结果**不直接入库**，地图先聚焦该景点并以半透明标记预览，右上角卡片确认后才添加（可选择加到第几天）
- **手动落点**：地图右键落点，同样走预览确认流程，手填名称与分类
- **地点字段**：备注、分类、天数、评分、已去过标记、链接
- **删除安全**：删计划前确认，删除后 5 秒内可撤销
- **备份与恢复**：文件菜单 ⌘E 导出全部计划为 JSON，⌘I 导入（追加合并 / 全量替换）

## 云端备份（导出/导入）

文件 → **导出所有计划…**（⌘E）：全部计划 + 去重后的地点写入一个 JSON，默认保存到 `~/Documents/Trip Plan/`（可改存 iCloud Drive 等任意网盘目录，文件进网盘即等于上云）。

文件 → **导入计划…**（⌘I）：选备份文件后可选：

- **追加合并**——保留本地现有数据；导入的计划以副本加入；**相同 `backupID` 的地点复用不重复**（多对多引用关系按文件重建）
- **全量替换**——清空本地后按文件完整恢复

多对多关系的正确恢复依赖模型上的稳定 `backupID: UUID`（新记录自动生成，导入时按它匹配）。

> 为什么不是 iCloud 自动同步：SwiftData + CloudKit 需要**付费 Apple Developer 账号**签名并开启 CloudKit 权限；本项目为 ad-hoc 签名自用 App，无法启用。导出 JSON + 网盘是零成本替代。将来若购买了开发者账号，可在 `ModelConfiguration` 加 `cloudKitDatabase: .private` 切换为自动同步，导出/导入代码仍可作为手动备份保留。

## 数据模型

```
Plan   name, startDate, endDate, destination(cityName/lat/lon/radius), createdAt
Place  name, latitude, longitude, notes, category, day, sortOrder,
       rating, visited, linkURL, photoPath(预留)
Plan  <->>  Place   多对多
```

**天由日期范围计算得出，不存 Day 实体**：改日期范围时天自动增减，无需维护实体集合。
未设日期的计划视为「单一无日期清单」（`dayCount == 1`）。

日期范围缩短时，原本排在已不存在天数的地点会**移到新的最后一天**，并提示移动了几个，不会丢失。

## 技术选型

| 项目 | 选择 | 原因 |
|---|---|---|
| 渲染 | MapKit / SwiftUI `Map` | 零 API key、零构建成本 |
| 搜索 | `MKLocalSearch` + `MKLocalSearchCompleter` | 与渲染同引擎，坐标系天然一致 |
| 存储 | SwiftData | `@Relationship` 多对多，样板代码最少 |
| 部署目标 | macOS 15+ | `MapSelection`（列表↔地图选中同步）需要 15.0 |
| 沙盒 | 关闭 | 自用 App，无需权限弹窗与公证 |

全链路**零第三方依赖、零 API key、零坐标转换**。

## 已知 MapKit 陷阱：不要设置 `MKLocalSearch.Request.region`

在 macOS 26（Xcode 26.6）上，**给 `MKLocalSearch.Request` 设置 `region` 会导致搜索必定失败**：

```
Error Domain=MKErrorDomain Code=4   // MKErrorPlacemarkNotFound
UserInfo={MKErrorGEOError=-8}
```

实测结论（用 Cocoa run loop 复现，非推测）：

| 请求构造方式 | 结果 |
|---|---|
| completion + **不设** region | ✅ 成功 |
| completion + `region = .world` | ❌ error 4 |
| completion + `region = 东京 60km`（正确匹配） | ❌ error 4 |
| completion + `region = 2km` | ❌ error 4 |
| `naturalLanguageQuery` + **不设** region | ✅ 成功 |
| `naturalLanguageQuery` + 任意 region | ❌ error 4 |

即**只要设了 region 就失败**，与值是否合理无关，也与是否使用 completion 无关。

因此本项目的做法是：**永不设置 `region`**，改用「在查询文本前拼城市名」来实现目的城市偏向（`PlaceSearchService.biasCity` / `biasedQuery`）。注意 `MKLocalSearchCompleter.region` **不受影响**（实测联想数量完全一致），只有 `MKLocalSearch.Request.region` 有此问题。

## 为什么不用 MapLibre

最初选择 MapLibre + OSM 瓦片，调研后放弃，原因与渲染能力无关，纯粹是分发问题：

- MapLibre Native 的 macOS target 确实存在且在维护（`platform/macos/`，Metal 渲染，CI 绿灯）
- 但**官方从未发布过 macOS 二进制**。官方 SPM 镜像只含 `ios-arm64`
- 维护者在 [issue #4088](https://github.com/maplibre/maplibre-native/issues/4088) 明确说明：macOS 开发者必须自行从源码构建，需要 CMake/Bazel、约 10GB 磁盘、1-2 小时
- `maplibre/swiftui-dsl` 的 SwiftUI 封装是 iOS-only（其 README 自述）
- Mapbox Maps v11 不支持 macOS

实测代价远超收益，故改用 MapKit。

## 删除语义（多对多）

`Plan` 与 `Place` 是多对多：一个地点可属于多个计划。

删除计划时：

1. 解除该计划与所有地点的关联
2. **仅当某地点不再被任何计划引用时**才真正删除它
3. 被其他计划共享的地点原样保留

SwiftData 无内置 undo manager，级联删除不可逆，因此删除前会把计划及其全部地点的**值快照**复制出来（`PlaceSnapshot` / `PlanDeletion`），撤销时按快照重建；仍存活的共享地点走重新链接，不会产生重复。

## 构建

```bash
open PinTrip.xcodeproj
# 或
xcodebuild -project PinTrip.xcodeproj -scheme PinTrip -configuration Debug build
```

## 已知限制

- 路径规划（原需求第 3 项）**尚未实现**，延后到 V2
- `photoPath` 字段已在模型中预留但 UI 未接入
- `Place.sortOrder` 在多对多共享下是全局值：同一地点在不同计划中共享同一顺序号
- 未开启 App Sandbox，故不适合直接分发

## 目录结构

```
PinTrip/
├── Models/          Plan.swift, Place.swift, DeletionSnapshot.swift
├── Views/           ContentView, PlanSidebar, PlaceListView, MapCanvasView, ...
└── Services/        PlaceSearchService, PlanStore, UndoController
```
