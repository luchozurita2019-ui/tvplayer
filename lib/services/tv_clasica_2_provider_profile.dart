class TvClasica2ProviderProfile {
  TvClasica2ProviderProfile._();

  static const String host = 'tv.m3uts.xyz';

  // Shared provider compatibility value supplied for authorized third-party
  // players. Explicit runtime/build configuration still takes precedence.
  static const String sharedXHash =
      'nzY51Dqljv2r0eXQuHb5CQX-QYyl2mcHHoPNgWyj5eP1_PZi9Q2mM_eIVTqWIGEX7hQc2_JDiPHXnbU2RtKal4FAAZsIa_opCMkdKe3ql0vc0HEbaU5WgZNjV-_AbbS8sQniXa0fSLMoeAGM-iPZ98N0jXVmKKKpF7UdeJBvtqCobk4BPZiNpdhX_jMnrIXgvl55cPl-7_tSHQLigzCo3GKLr8w_88tJvu7dub-s42iEKwVOzrOD_fLYdyuqDhmR5lHzcrF58_efZ3rZO7ao_uN7BPWdEifcj6t8JkF0RAnQJYiPVp3v37c3sdCwcykUlVWpccKIxg6haOpgwQBl5RJT2l6fgXsnwvApg0CJS_bCkW-G2l0Wm-PuQBMUZZrpQCkBhI3Nd3tb_4YRvXZOVeLQ9XLKEueM0_OuX3EcQ38GLDMRgGwc_4RK_4bvJhpFqUybQ9GzRkniN8a-6O64vkjqVbgJjhO-x-jBE6H9ZeVTXl3zMDsluIVv4hCU7q8cEPdom3RLwB1TN3Sptk02Jg';

  static bool appliesToHost(String value) =>
      value.trim().toLowerCase() == host;
}
