#ifndef OPTIMIZATOR_SMC_H
#define OPTIMIZATOR_SMC_H

#ifdef __cplusplus
extern "C" {
#endif

/// Відкрити з'єднання з AppleSMC. 0 = успіх. Читання працює без root, запис — лише від root.
int smc_open(void);
void smc_close(void);

/// Прочитати ключ як число (підтримує flt, fpe2, sp78, ui8, ui16, ui32). 0 = успіх.
int smc_read_number(const char *key, double *out);
/// Записати число у ключ у його рідному форматі. 0 = успіх.
int smc_write_number(const char *key, double value);

int smc_fan_count(void);
/// manual: 1 — ручний режим, 0 — автоматичний. 0 = успіх.
int smc_fan_set_manual(int fan, int manual);
int smc_fan_set_target(int fan, double rpm);

/// Максимальна валідна температура серед списку ключів, або -1.
double smc_max_temp(const char *const *keys, int count);

#ifdef __cplusplus
}
#endif
#endif
