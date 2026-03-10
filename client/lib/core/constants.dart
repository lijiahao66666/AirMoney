class AppConstants {
  /// 支出分类
  static const List<String> expenseCategories = [
    '餐饮',
    '交通',
    '购物',
    '娱乐',
    '居家',
    '医疗',
    '教育',
    '其他',
  ];

  /// 收入分类
  static const List<String> incomeCategories = [
    '工资',
    '奖金',
    '兼职',
    '理财收益',
    '红包',
    '其他',
  ];

  static const List<String> payMethods = [
    '微信',
    '支付宝',
    '现金',
    '银行卡',
    '其他',
  ];

  static const Map<String, String> categoryIcons = {
    '餐饮': 'restaurant',
    '交通': 'directions_car',
    '购物': 'shopping_cart',
    '娱乐': 'movie',
    '居家': 'home',
    '医疗': 'local_hospital',
    '教育': 'school',
    '工资': 'work',
    '奖金': 'emoji_events',
    '兼职': 'handyman',
    '理财收益': 'trending_up',
    '红包': 'redeem',
    '其他': 'more_horiz',
  };
}
