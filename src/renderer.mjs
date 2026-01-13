const console = document.getElementById('info');

window.electronAPI.setInfoText((value) => {
  // const oldValue = Number(counter.innerText)
  // const newValue = oldValue + value
  console.innerText = value;
});
