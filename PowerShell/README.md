# 说明

## auto_rewrite_v1.ps1

批量自动处理仓库：修改指定仓库中(本地已克隆)所有 commits 中的 email，并推送到远端
**Notice:**

- 需要指定默认分支为master/main
- 如果还需要修改名字则需修改脚本内容：

```powershell
    # 新旧姓名
    $newName = "Your New Name"
    $oldName = "Old Name in Git History"

    # 新旧邮箱
    $newEmail = "921232958@qq.com"
    $oldEmail = "yangyukai@zwcad.com"

    # mailmap 里的格式：New Name <newEmail> Old Name <oldEmail>
    $mailmapText = "$newName <$newEmail> $oldName <$oldEmail>"
```

## auto_rewrite_v2.ps1

批量自动处理仓库：修改指定仓库中(本地未克隆)所有 commits 中的 email，并推送到远端(会克隆远端仓库到本地)
**Notice:**

- 需要指定每个仓库对应的分支
- 如果还需要修改名字则需修改脚本内容：

```powershell
    # 新旧姓名
    $newName = "Your New Name"
    $oldName = "Old Name in Git History"

    # 新旧邮箱
    $newEmail = "921232958@qq.com"
    $oldEmail = "yangyukai@zwcad.com"

    # mailmap 里的格式：New Name <newEmail> Old Name <oldEmail>
    $mailmapText = "$newName <$newEmail> $oldName <$oldEmail>"
```
