-- 技能成长与综合等级的第二版持久化结构。
-- 生产 SQLite 适配器应按迁移序号执行；当前文件仓储使用等价 JSON 迁移。
ALTER TABLE characters
ADD COLUMN comprehensive_level INTEGER NOT NULL DEFAULT 10
CHECK (comprehensive_level >= 10);

ALTER TABLE character_skills
ADD COLUMN fractional_experience REAL NOT NULL DEFAULT 0
CHECK (fractional_experience >= 0 AND fractional_experience < 1);
