# PinTrip

macOS 旅游地点标注与规划工具。搜索地点 → 加入计划 → 在地图上查看全部标注 → 按计划一键管理。

## 功能

- **旅游计划**：新建/删除计划，每个计划可绑定目的地城市
- **地点搜索**：`MKLocalSearchCompleter` 边打边联想，选中即加入当前计划
- **地图标注**：SwiftUI `Map` 显示计划内全部地点，按分类着色
- **手动落点**：地图上右键「在此添加标注」，手填名称与分类
- **地点字段**：备注、分类、行程顺序/天数、评分、已去过标记、链接
- **删除安全**：删计划前确认，删除后 5 秒内可撤销

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
