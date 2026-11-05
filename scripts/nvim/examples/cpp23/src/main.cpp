#include <expected>
#include <iostream>
#include <string_view>

/// @brief 验证 C++23 标准库支持；返回成功退出码。
/// @return 验证成功时返回 0，失败时返回 1。
int main()
{
    const std::expected<int, std::string_view> result{23};
    if (!result.has_value())
    {
        return 1;
    }
    std::cout << "C++" << *result << " ready\n";
    return *result == 23 ? 0 : 1;
}
