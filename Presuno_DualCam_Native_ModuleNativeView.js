//  Created by react-native-create-bridge

import React, { Component } from 'react'
import { requireNativeComponent } from 'react-native'

const Presuno_DualCam_Native_Module = requireNativeComponent('Presuno_DualCam_Native_Module', Presuno_DualCam_Native_ModuleView)

export default class Presuno_DualCam_Native_ModuleView extends Component {
  render () {
    return <Presuno_DualCam_Native_Module {...this.props} />
  }
}

// Presuno_DualCam_Native_ModuleView.propTypes = {
//   exampleProp: React.PropTypes.any
// }
