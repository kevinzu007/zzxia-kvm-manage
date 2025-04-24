## vm-snapshot.sh 测试计划

**测试目标：** 验证 `vm-snapshot.sh` 脚本在离线和在线模式下的快照创建、列出、回滚和删除功能。

**测试环境：**

- 虚拟机：`prod-192-168-2-11-mtss-deploy`
- 初始状态：`shut off`
- 脚本：`./vm-snapshot.sh` (版本 1.2.6 或更高)
- 当前快照：无 (根据之前的输出)

### 第一部分：离线模式测试 (虚拟机保持关机)

1. **创建第一个离线快照:**
   - 命令: `./vm-snapshot.sh -c offline_snap1 -n prod-192-168-2-11-mtss-deploy`
   - 预期：提示确认，确认后为所有 qcow2 磁盘创建名为 `offline_snap1` 的内部快照，并报告成功。
2. **列出离线快照 (验证创建):**
   - 命令: `./vm-snapshot.sh -l -n prod-192-168-2-11-mtss-deploy`
   - 预期：列出每个 qcow2 磁盘，并显示其下包含 `offline_snap1` 快照。
3. **创建第二个离线快照:**
   - 命令: `./vm-snapshot.sh -c offline_snap2 -n prod-192-168-2-11-mtss-deploy`
   - 预期：成功创建名为 `offline_snap2` 的内部快照。
4. **列出离线快照 (验证多个):**
   - 命令: `./vm-snapshot.sh -l -n prod-192-168-2-11-mtss-deploy`
   - 预期：列出每个 qcow2 磁盘，并显示其下包含 `offline_snap1` 和 `offline_snap2` 快照。
5. **回滚到第一个离线快照:**
   - 命令: `./vm-snapshot.sh -r offline_snap1 -n prod-192-168-2-11-mtss-deploy`
   - 预期：提示确认，确认后将所有 qcow2 磁盘回滚到 `offline_snap1` 状态，并报告成功。
6. **删除第二个离线快照:**
   - 命令: `./vm-snapshot.sh -d offline_snap2 -n prod-192-168-2-11-mtss-deploy`
   - 预期：提示确认，确认后删除所有 qcow2 磁盘上的 `offline_snap2` 快照，并报告成功。
7. **列出离线快照 (验证删除):**
   - 命令: `./vm-snapshot.sh -l -n prod-192-168-2-11-mtss-deploy`
   - 预期：列出每个 qcow2 磁盘，只显示 `offline_snap1` 快照。
8. **`测试 --force 删除不存在的快照:`**
   - 命令: `./vm-snapshot.sh -d non_existent_snap -n prod-192-168-2-11-mtss-deploy --force`
   - 预期：脚本报告在磁盘上找不到 `non_existent_snap`，但由于使用了 `--force`，会跳过错误并完成执行（可能伴有警告信息），不会中止。
9. **清理离线快照:**
   - 命令: `./vm-snapshot.sh -d offline_snap1 -n prod-192-168-2-11-mtss-deploy`
   - 预期：成功删除 `offline_snap1`。
   - 命令: `./vm-snapshot.sh -l -n prod-192-168-2-11-mtss-deploy`
   - 预期：报告未找到任何内部快照。

### 第二部分：在线模式测试

**准备工作:**

- **启动虚拟机:** `virsh start prod-192-168-2-11-mtss-deploy`
- **确认虚拟机状态:** `virsh domstate prod-192-168-2-11-mtss-deploy` (应为 `running`)
- **(重要) 确认 QEMU Guest Agent:** 检查虚拟机内部 `qemu-guest-agent` 服务是否已安装并正在运行。
- **(重要) 解决 SELinux/AppArmor 问题:** 确保虚拟机内部的 SELinux/AppArmor 策略允许 `qemu-ga` 执行 `fsfreeze` 操作（例如，通过 `setenforce 0` 临时测试，或配置正确的规则）。

**测试步骤:**

1. **创建第一个在线快照 (仅磁盘，推荐):**
   - 命令: `./vm-snapshot.sh -c live_snap1_disk -n prod-192-168-2-11-mtss-deploy --live --disk-only`
   - 预期：如果 Guest Agent 运行正常且 SELinux/AppArmor 允许，会尝试冻结文件系统。成功创建名为 `live_snap1_disk` 的外部快照（仅磁盘状态）。
2. **列出在线快照 (验证创建):**
   - 命令: `./vm-snapshot.sh -l -n prod-192-168-2-11-mtss-deploy --live`
   - 预期：列出包含 `live_snap1_disk` 的外部快照信息。
3. **创建第二个在线快照 (含内存，如果需要测试):**
   - **注意:** 根据之前的测试，此环境可能不支持包含内存的外部快照 (`error: unsupported configuration: disk 'vda' must use snapshot mode 'internal'`)。
   - **`如果仍要尝试 (需要 --no-quiesce)`**:
     - 命令: `./vm-snapshot.sh -c live_snap2_full_noq -n prod-192-168-2-11-mtss-deploy --live --no-quiesce`
     - 预期：可能失败，或成功创建包含内存但磁盘状态为“崩溃一致”的快照。
   - **建议:** 跳过此步骤或标记为不适用，专注于测试仅磁盘快照。
4. **列出在线快照 (验证多个):**
   - 命令: `./vm-snapshot.sh -l -n prod-192-168-2-11-mtss-deploy --live`
   - 预期：列出已成功创建的快照（例如 `live_snap1_disk`）。
5. **回滚到第一个在线快照 (live_snap1_disk):**
   - **注意:** 根据之前的测试，即使在关机状态下，回滚仅磁盘的外部快照也可能失败 (`error: internal error: Invalid target domain state 'disk-snapshot'`)。
   - **尝试关机后回滚:**
     1. 关闭虚拟机: `virsh shutdown prod-192-168-2-11-mtss-deploy` (等待其完全关闭)
     2. 确认状态: `virsh domstate prod-192-168-2-11-mtss-deploy` (应为 `shut off`)
     3. 执行脚本回滚: `./vm-snapshot.sh -r live_snap1_disk -n prod-192-168-2-11-mtss-deploy --live`
     4. **预期:** 可能仍然失败并报告 `Invalid target domain state 'disk-snapshot'` 错误。
   - **如果脚本失败，尝试直接用 virsh:**
     1. (虚拟机保持关机)
     2. 直接执行: `virsh snapshot-revert prod-192-168-2-11-mtss-deploy live_snap1_disk`
     3. **预期:** 可能仍然失败。如果直接执行也失败，则确认是 libvirt/QEMU 的问题。
   - **如果回滚失败:** 标记此步骤为失败，并考虑跳过在线回滚测试，直接进行第 15 步的在线删除/合并测试。
6. **(高危操作) 在线删除/合并当前层:**
   - **准备:** 确保虚拟机正在运行 (`virsh start prod-192-168-2-11-mtss-deploy`)。
   - 命令: `./vm-snapshot.sh -d merge_current -n prod-192-168-2-11-mtss-deploy --live`
   - 预期：**出现高 I/O 风险警告**。提示确认。确认后，脚本对所有磁盘执行 `virsh blockcommit --active --pivot`。**此过程可能耗时较长，并显著影响 VM 性能。** 操作完成后报告成功或失败。快照名称 `merge_current` 仅用于标识操作。
7. **列出在线快照 (验证合并):**
   - 命令: `./vm-snapshot.sh -l -n prod-192-168-2-11-mtss-deploy --live`
   - 预期：快照列表**仍然会显示** `live_snap1_disk` 的元数据记录，因为 `blockcommit` 不会删除它。但是，虚拟机当前的磁盘状态已经不再基于此快照文件。要验证合并效果，可以检查 `virsh domblklist prod-192-168-2-11-mtss-deploy` 的输出，确认磁盘源文件是否已变回基础镜像路径。
8. **`测试 --force 在线删除:`**
   - **准备:** 如果上一步合并成功，可能需要先再创建一个在线快照（例如 `live_snap_temp`）才能测试合并。
   - 命令: `./vm-snapshot.sh -d merge_again -n prod-192-168-2-11-mtss-deploy --live --force`
   - 预期：**出现高 I/O 风险警告**。由于使用了 `--force`，**跳过最终确认提示**，直接开始执行 blockcommit。
9. **清理剩余在线快照 (如果还有):**
   - 根据 `virsh snapshot-list prod-192-168-2-11-mtss-deploy` 的结果，**需要手动**使用 `virsh snapshot-delete <vm> <snapname> --metadata` 来删除不再需要的快照元数据记录（例如 `live_snap1_disk`）。如果快照链复杂，可能还需要配合 `virsh blockcommit` (可能需要关机操作) 来清理磁盘文件。**注意：脚本当前的在线删除是合并当前层，并不能直接删除任意一个旧的外部快照元数据。**

### 第三部分：边界和错误条件测试 (可选)

- 尝试在 VM 运行时执行离线操作 (预期：报错提示需要关机)。
- 尝试对不存在的 VM 执行操作 (预期：报错提示 VM 不存在)。
- 尝试创建/删除/回滚时使用不存在的快照名称 (不带 `--force`) (预期：报错提示快照不存在)。
- (在线模式) 如果 Guest Agent 未运行，尝试创建快照 (不带 `--no-quiesce`)，观察行为 (预期：可能创建成功但有警告，或创建失败)。
- (在线模式) 尝试创建快照时不带 `--disk-only`，观察内存文件是否生成以及所需时间。

请按照这个计划逐步执行命令，并仔细观察脚本的输出和虚拟机的状态变化，与预期结果进行对比。祝测试顺利！


