export default {
  methods: {
    useInstallationName(str = '', installationName) {
      return str.replace(/Tuskeechat/g, installationName);
    },
  },
};
