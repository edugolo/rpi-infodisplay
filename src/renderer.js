const ipAddressEl = document.getElementById('ipAddress');
const infoEl = document.getElementById('info');

window.electronAPI.setInfoText((value) => {
  const data = JSON.parse(value);
  
  // Extract and display IPv4 prominently
  const ip = data.device?.system?.defaultNetworkInterface?.ip4 || 'No IP';
  ipAddressEl.innerText = ip;
  
  // Display the rest of the info
  infoEl.innerText = value;
});
